# Eta DeepSeek Unbound — 编译说明

## 这是什么

一个 LSPosed 模块，目标 App 为 `com.deepseek.chat`（DeepSeek 官方 Android 客户端）。
作用是在客户端侧改写请求字段，**不改服务端策略**。

## 最重要的技术细节（请先看这段）

目标类 `h02` 的字段 `e`(thinking_enabled)、`f`(search_enabled)、`g`(prompt)
都是 **PUBLIC FINAL**（access flags `0x0011`）。

**Android ART 上直接 `Field.set()` 修改 final 字段会抛 `IllegalAccessException`。**

所以必须先反射清掉 `Field.modifiers` 里的 FINAL 位（`0x10`），再写入。
代码里 `stripFinal()` 就是干这个的：

```java
Field modifiers = Field.class.getDeclaredField("modifiers");
modifiers.setAccessible(true);
modifiers.setInt(f, modifiers.getInt(f) & ~0x10);
```

**如果编译时把这段优化掉或忽略，模块会加载成功但完全不生效** ——
因为异常被 catch 静默吞掉了。这一点我已经在真机上验证过。

## 编译

```bash
# 编译依赖（仅编译期，不要打进 dex）
curl -L -o xposed-api-82.jar https://api.xposed.info/framework/api-82.jar

mkdir -p build/classes
javac -source 8 -target 8 \
      -cp xposed-api-82.jar \
      -d build/classes \
      src/com/eta/dseek/MainHook.java

# 只转自己的 class，不要用任何含 Xposed API 的 dex 当基底
d8 --min-api 24 --output build/dex build/classes/com/eta/dseek/*.class
```

### 两个必须满足的约束

**1. dex 里不能包含 Xposed API 类的实现**

否则 LSPosed 拒绝加载并报：
```
Cannot load module: com.eta.dseek.unbound
The Xposed API classes are compiled into the module's APK.
```

验证：`dexdump -f classes.dex | grep "Class descriptor"` 应该只有
`com.eta.dseek.MainHook` 和它的内部类（2-3 个），不是 180 多个。

**2. 保留 stripFinal 逻辑**

d8 的某些优化级别可能会把对 `Field.modifiers` 的反射操作当成无用代码。
建议用 `d8 --min-api 24` 默认优化级别，不要开 `--release` 全优化。

## 打包

APK 根目录：

```
AndroidManifest.xml      (template/ 里的，包名 com.eta.dseek.unbound)
assets/xposed_init       (内容: com.eta.dseek.MainHook)
classes.dex
resources.arsc           (template/ 里的)
```

```bash
cd build/apk && zip -qr ../unsigned.apk .
apksigner sign --ks your.jks --out EtaDSU-signed.apk ../unsigned.apk
```

`build.sh` 已写好完整流程，环境齐的话 `bash build.sh` 直接出签名 APK。

## 逆向依据

业务层被 R8 混淆，请求体数据类为短名：

| 类 | 用途 |
|---|---|
| `h02` | ChatFullCompletionRequest |
| `f02` | ChatCompletionRequest |
| `gz1` | ChatEditMessageRequest |

`h02` 字段表（12 个）：

| 字段 | 类型 | 含义 | access |
|---|---|---|---|
| a | String | chat_session_id | PUBLIC FINAL |
| b | Integer | model_type | PUBLIC FINAL |
| c | String | ? | PUBLIC FINAL |
| d | List | ref_file_ids | PUBLIC FINAL |
| **e** | **Z** | **thinking_enabled** | **PUBLIC FINAL** |
| **f** | **Z** | **search_enabled** | **PUBLIC FINAL** |
| **g** | **String** | **prompt** | **PUBLIC FINAL** |
| h | Z | preempt | PUBLIC FINAL |
| i | String | audio_id | PUBLIC FINAL |
| j | String | parent_message_id | PUBLIC FINAL |
| k | String | action | PUBLIC FINAL |
| l | String | shumei_device_id | PUBLIC FINAL |

构造器签名：
```
(ILjava/lang/String;Ljava/lang/Integer;Ljava/lang/String;
 Ljava/util/List;ZZLjava/lang/String;Z
 Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
```

请求路径：`/api/v0/chat/completion`

服务端拦截 biz_code：`CONTENT_FILTER`、`RATE_LIMITED`、`TOO_MANY_REQUESTS`、`CONTENT_TOO_LONG`

## 已在真机验证的部分

- 模块能被 LSPosed 正常加载：日志 `EtaDSU active in com.deepseek.chat`
- 作用域绑定 `com.deepseek.chat` 成功
- `h02`/`f02`/`gz1` 三个类在实际 APK 中确实存在（classes.dex 顶层，80 处引用）
- hook 逻辑字节码完整（hookRequests / forceFlags / injectPrefix 都在）

## 未验证 / 已知问题

- **字段改写是否真的生效**：上一版因为没清 FINAL 位而静默失败，本版修复但尚未编译验证
- 短名类在不同 App 版本可能变化
- 即使字段改成功，服务端 biz_code 拦截仍在服务端，客户端改不到

## 编译后怎么验证

启动 DeepSeek，看 LSPosed 日志：

```
EtaDSU: installing in com.deepseek.chat
EtaDSU: hooked h02
EtaDSU: patched h02      <- 看到这行说明字段真的写进去了
```

然后手动把「深度思考」关掉，发一条消息，看它是否被强制开启。

如果出现 `IllegalAccessException` 的堆栈，说明 stripFinal 没生效，检查 d8 优化级别。
