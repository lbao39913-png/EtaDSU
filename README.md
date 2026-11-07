# EtaDSU

LSPosed module for the DeepSeek Android client (`com.deepseek.chat`).

Rewrites the request model fields of the three chat request classes on the
client side. It does **not** and cannot change anything server-side.

## Status: working

Verified on a real device. LSPosed log after sending a message:

```
EtaDSU: installing in com.deepseek.chat
EtaDSU: hooked h02
EtaDSU: hooked f02
EtaDSU: hooked gz1
EtaDSU: patched h02
```

`patched h02` means the constructor ran and the fields were actually written.

## What it does

| Action | Field |
|---|---|
| force `thinking_enabled` = true | `h02.e`, `f02.e`, `gz1.e` |
| force `search_enabled` = true | `h02.f`, `f02.f`, `gz1.f` |
| prepend a prefix to `prompt` | `h02.g`, `f02.g`, `gz1.g` |

## The one thing that matters

Those fields are declared **`PUBLIC FINAL`** in the target app
(access flags `0x0011`).

On Android ART, `Field.set()` on a final field throws
`IllegalAccessException`. Every write must first clear the FINAL bit in
`Field.modifiers`:

```java
Field mod = Field.class.getDeclaredField("modifiers");
mod.setAccessible(true);
mod.setInt(f, mod.getInt(f) & ~0x10);
```

Without this the module loads fine, hooks attach fine, and **nothing
happens** — the exception is swallowed by the catch block. This was the
single reason an earlier build silently did nothing.

## Why no Xposed API jar is needed

The entry point must match LSPosed's reflective lookup exactly:

```java
void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam)
```

An `Object` parameter compiles but is never called.

Rather than downloading `api-82.jar` (no stable public URL), this repo
carries minimal signature stubs under `api-stub/`. They are compiled to
`api-stub.jar` and used only on the javac/d8 classpath, so `classes.dex`
contains **type references only**, never Xposed API class definitions.
LSPosed rejects modules that embed the API:

```
Cannot load module: ... The Xposed API classes are compiled into the module's APK.
```

The build verifies this and fails if `de/robv/android/xposed` appears in
`Class descriptor` output.

## Build

Push to `main`. GitHub Actions compiles, signs, and commits `EtaDSU.apk`
back into the repo.

The APK is always at:

```
https://raw.githubusercontent.com/lbao39913-png/EtaDSU/main/EtaDSU.apk
```

Pipeline steps: install cmdline-tools → build `api-stub.jar` → `javac` →
`d8` → verify dex → zip → `zipalign` → `apksigner`.

## Install

1. `pm install -r EtaDSU.apk`
2. Enable the module in LSPosed, set scope to `com.deepseek.chat`
3. Reboot (LSPosed reads its config at boot)

## Reverse engineering notes

Business layer is R8-obfuscated; the request data classes use short names:

| Class | Purpose |
|---|---|
| `h02` | ChatFullCompletionRequest |
| `f02` | ChatCompletionRequest |
| `gz1` | ChatEditMessageRequest |

`h02` fields (all `PUBLIC FINAL`):

| Field | Type | Meaning |
|---|---|---|
| a | String | chat_session_id |
| b | Integer | model_type |
| c | String | — |
| d | List | ref_file_ids |
| **e** | **Z** | **thinking_enabled** |
| **f** | **Z** | **search_enabled** |
| **g** | **String** | **prompt** |
| h | Z | preempt |
| i | String | audio_id |
| j | String | parent_message_id |
| k | String | action |
| l | String | shumei_device_id |

Constructor signature:

```
(ILjava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/util/List;
 ZZLjava/lang/String;ZLjava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
```

Endpoint: `/api/v0/chat/completion`

## Limits

Server-side refusal is not reachable from the client. The app maps these
server biz_codes to UI messages; changing request fields does not bypass
them:

```
CONTENT_FILTER  RATE_LIMITED  TOO_MANY_REQUESTS  CONTENT_TOO_LONG
```

Short class names change between app versions. If `hooked h02` disappears
from the log, re-derive them with:

```bash
dexdump -f classes.dex | grep "Class descriptor" | head -100
```
