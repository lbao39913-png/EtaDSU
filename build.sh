#!/usr/bin/env bash
# Eta DeepSeek Unbound — 一键构建脚本
# 依赖: javac, d8, apksigner, unzip, zip  (Android SDK build-tools)
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PKG_NAME="com.eta.dseek.unbound"
API_JAR="xposed-api-82.jar"
KS="${KS:-$HOME/.android/debug.keystore}"

echo "==> [1/5] 获取 Xposed API"
[ -f "$API_JAR" ] || curl -L -o "$API_JAR" https://api.xposed.info/framework/api-82.jar

echo "==> [2/5] 编译 Java"
rm -rf build && mkdir -p build/classes
javac -source 8 -target 8 -nowarn \
      -cp "$API_JAR" \
      -d build/classes \
      src/com/eta/dseek/MainHook.java

echo "==> [3/5] 转 dex（关键：只转自己的类）"
d8 --min-api 24 --output build/dex build/classes/com/eta/dseek/*.class

DEX="build/dex/classes.dex"
[ -f "$DEX" ] || { echo "d8 没产出 classes.dex"; exit 1; }

# 校验：dex 里不能出现 Xposed API 类的定义
if strings "$DEX" | grep -q "Lde/robv/android/xposed/XposedBridge;"; then
    echo "!! 警告: dex 中出现了 Xposed API 类引用"
    echo "   注意: 方法签名里的类型引用是正常的，只有类*定义*才会导致 LSPosed 拒绝加载"
fi
echo "    dex 大小: $(stat -c%s "$DEX") 字节"

echo "==> [4/5] 组装 APK"
rm -rf build/apk && mkdir -p build/apk
cp template/AndroidManifest.xml build/apk/
cp template/resources.arsc     build/apk/
mkdir -p build/apk/assets
printf 'com.eta.dseek.MainHook' > build/apk/assets/xposed_init
cp "$DEX" build/apk/classes.dex

( cd build/apk && zip -qr ../unsigned.apk . )

echo "==> [5/5] 签名"
if [ ! -f "$KS" ]; then
    echo "    未找到 keystore，生成 debug 签名..."
    mkdir -p "$(dirname "$KS")"
    keytool -genkeypair -v -keystore "$KS" -alias androiddebugkey \
            -keyalg RSA -keysize 2048 -validity 10000 \
            -storepass android -keypass android \
            -dname "CN=Android Debug,O=Android,C=US" 2>/dev/null
fi

apksigner sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
               --out EtaDSU-signed.apk build/unsigned.apk
apksigner verify --print-certs EtaDSU-signed.apk | head -5

echo
echo "完成: $ROOT/EtaDSU-signed.apk"
echo "安装: adb install -r EtaDSU-signed.apk"
