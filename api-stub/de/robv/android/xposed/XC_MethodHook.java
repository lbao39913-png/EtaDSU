package de.robv.android.xposed;

public abstract class XC_MethodHook {

    public static class Unhook implements IXUnhook {
        public void unhook() {}
    }

    public interface IXUnhook {
        void unhook();
    }

    protected void beforeHookedMethod(MethodHookParam param) throws Throwable {}
    protected void afterHookedMethod(MethodHookParam param) throws Throwable {}

    public static final class MethodHookParam {
        public Object thisObject;
        public Object[] args;
        public Object getResult() { return null; }
        public void setResult(Object r) {}
        public Throwable getThrowable() { return null; }
    }
}
