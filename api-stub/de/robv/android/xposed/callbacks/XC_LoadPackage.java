package de.robv.android.xposed.callbacks;

import de.robv.android.xposed.XC_MethodHook;

public abstract class XC_LoadPackage {
    public static final class LoadPackageParam extends XCallback.Param {
        public String packageName;
        public ClassLoader classLoader;
        public String processName;
        public Object appInfo;
        public boolean isFirstApplication;
    }
}
