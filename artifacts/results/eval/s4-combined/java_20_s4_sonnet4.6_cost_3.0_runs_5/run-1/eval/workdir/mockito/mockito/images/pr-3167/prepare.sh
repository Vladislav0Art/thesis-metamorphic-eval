#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout b6554b29ed6c204a0dd4b8a670877fe0ba2e808b

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..5339364c2 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -16,18 +16,18 @@ import java.util.function.Function;
 
 public class InlineByteBuddyMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
-    private final InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
+    private final InlineDelegatingByteBuddyMockFactory inlineDelegateByteBuddyMockMaker;
 
     public InlineByteBuddyMockMaker() {
         try {
-            inlineDelegateByteBuddyMockMaker = new InlineDelegateByteBuddyMockMaker();
+            inlineDelegateByteBuddyMockMaker = new InlineDelegatingByteBuddyMockFactory();
         } catch (NoClassDefFoundError e) {
             Reporter.missingByteBuddyDependency(e);
             throw e;
         }
     }
 
-    InlineByteBuddyMockMaker(InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
+    InlineByteBuddyMockMaker(InlineDelegatingByteBuddyMockFactory inlineDelegateByteBuddyMockMaker) {
         this.inlineDelegateByteBuddyMockMaker = inlineDelegateByteBuddyMockMaker;
     }
 
@@ -53,13 +53,13 @@ public class InlineByteBuddyMockMaker
 
     @Override
     public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return inlineDelegateByteBuddyMockMaker.createMock(settings, handler);
+        return inlineDelegateByteBuddyMockMaker.createMockInstance(settings, handler);
     }
 
     @Override
     public <T> Optional<T> createSpy(
             MockCreationSettings<T> settings, MockHandler handler, T instance) {
-        return inlineDelegateByteBuddyMockMaker.createSpy(settings, handler, instance);
+        return inlineDelegateByteBuddyMockMaker.createSpyInstance(settings, handler, instance);
     }
 
     @Override
@@ -69,7 +69,7 @@ public class InlineByteBuddyMockMaker
 
     @Override
     public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
-        inlineDelegateByteBuddyMockMaker.resetMock(mock, newHandler, settings);
+        inlineDelegateByteBuddyMockMaker.resetMockInterceptor(mock, newHandler, settings);
     }
 
     @Override
@@ -80,7 +80,7 @@ public class InlineByteBuddyMockMaker
     @Override
     public <T> StaticMockControl<T> createStaticMock(
             Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
-        return inlineDelegateByteBuddyMockMaker.createStaticMock(type, settings, handler);
+        return inlineDelegateByteBuddyMockMaker.createStaticMockController(type, settings, handler);
     }
 
     @Override
@@ -89,12 +89,12 @@ public class InlineByteBuddyMockMaker
             Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
             Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
             MockedConstruction.MockInitializer<T> mockInitializer) {
-        return inlineDelegateByteBuddyMockMaker.createConstructionMock(
+        return inlineDelegateByteBuddyMockMaker.createConstructionMockController(
                 type, settingsFactory, handlerFactory, mockInitializer);
     }
 
     @Override
     public void clearAllCaches() {
-        inlineDelegateByteBuddyMockMaker.clearAllCaches();
+        inlineDelegateByteBuddyMockMaker.clearCachesAndMocks();
     }
 }
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegatingByteBuddyMockFactory.java
similarity index 56%
rename from src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
rename to src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegatingByteBuddyMockFactory.java
index 4cb0b40c0..0e717bbbc 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegatingByteBuddyMockFactory.java
@@ -100,12 +100,12 @@ import static org.mockito.internal.util.StringUtil.join;
  * support this feature.
  */
 @SuppressSignatureCheck
-class InlineDelegateByteBuddyMockMaker
+class InlineDelegatingByteBuddyMockFactory
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
 
-    private static final Instrumentation INSTRUMENTATION;
+    private static final Instrumentation JVM_AGENT;
 
-    private static final Throwable INITIALIZATION_ERROR;
+    private static final Throwable STARTUP_EXCEPTION;
 
     static {
         Instrumentation instrumentation;
@@ -145,7 +145,7 @@ class InlineDelegateByteBuddyMockMaker
                     String source =
                             "org/mockito/internal/creation/bytebuddy/inject/MockMethodDispatcher";
                     InputStream inputStream =
-                            InlineDelegateByteBuddyMockMaker.class
+                            InlineDelegatingByteBuddyMockFactory.class
                                     .getClassLoader()
                                     .getResourceAsStream(source + ".raw");
                     if (inputStream == null) {
@@ -156,7 +156,7 @@ class InlineDelegateByteBuddyMockMaker
                                                 + ".raw",
                                         "",
                                         "The class loader responsible for looking up the resource: "
-                                                + InlineDelegateByteBuddyMockMaker.class
+                                                + InlineDelegatingByteBuddyMockFactory.class
                                                         .getClassLoader()));
                     }
                     outputStream.putNextEntry(new JarEntry(source + ".class"));
@@ -203,521 +203,48 @@ class InlineDelegateByteBuddyMockMaker
             instrumentation = null;
             initializationError = throwable;
         }
-        INSTRUMENTATION = instrumentation;
-        INITIALIZATION_ERROR = initializationError;
+        JVM_AGENT = instrumentation;
+        STARTUP_EXCEPTION = initializationError;
     }
 
-    private final BytecodeGenerator bytecodeGenerator;
+    private final BytecodeGenerator classGenerator;
 
-    private final WeakConcurrentMap<Object, MockMethodInterceptor> mocks =
+    private final WeakConcurrentMap<Object, MockMethodInterceptor> interceptorMap =
             new WeakConcurrentMap<>(false);
 
-    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> mockedStatics =
+    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> staticInterceptorLocal =
             new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
     private final DetachedThreadLocal<Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>>>
-            mockedConstruction = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
+        constructionCallbacksLocal = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
-    private final ThreadLocal<Class<?>> currentMocking = ThreadLocal.withInitial(() -> null);
+    private final ThreadLocal<Class<?>> mockingTarget = ThreadLocal.withInitial(() -> null);
 
-    private final ThreadLocal<Object> currentSpied = new ThreadLocal<>();
+    private final ThreadLocal<Object> spiedInstanceHolder = new ThreadLocal<>();
 
-    InlineDelegateByteBuddyMockMaker() {
-        if (INITIALIZATION_ERROR != null) {
-            String detail;
-            if (PlatformUtils.isAndroidPlatform() || PlatformUtils.isProbablyTermuxEnvironment()) {
-                detail =
-                        "It appears as if you are trying to run this mock maker on Android which does not support the instrumentation API.";
-            } else {
-                try {
-                    if (INITIALIZATION_ERROR instanceof NoClassDefFoundError
-                            && INITIALIZATION_ERROR.getMessage() != null
-                            && INITIALIZATION_ERROR
-                                    .getMessage()
-                                    .startsWith("net/bytebuddy/agent/")) {
-                        detail =
-                                join(
-                                        "It seems like you are running Mockito with an incomplete or inconsistent class path. Byte Buddy Agent could not be loaded.",
-                                        "",
-                                        "Byte Buddy Agent is available on Maven Central as 'net.bytebuddy:byte-buddy-agent' with the module name 'net.bytebuddy.agent'.",
-                                        "Normally, your IDE or build tool (such as Maven or Gradle) should take care of your class path completion but ");
-                    } else if (Class.forName("javax.tools.ToolProvider")
-                                    .getMethod("getSystemJavaCompiler")
-                                    .invoke(null)
-                            == null) {
-                        detail =
-                                "It appears as if you are running on a JRE. Either install a JDK or add JNA to the class path.";
-                    } else {
-                        detail =
-                                "It appears as if your JDK does not supply a working agent attachment mechanism.";
-                    }
-                } catch (Throwable ignored) {
-                    detail =
-                            "It appears as if you are running an incomplete JVM installation that might not support all tooling APIs";
-                }
-            }
-            throw new MockitoInitializationException(
-                    join(
-                            "Could not initialize inline Byte Buddy mock maker.",
-                            "",
-                            detail,
-                            Platform.describe()),
-                    INITIALIZATION_ERROR);
-        }
-
-        ThreadLocal<Class<?>> currentConstruction = new ThreadLocal<>();
-        ThreadLocal<Boolean> isSuspended = ThreadLocal.withInitial(() -> false);
-        Predicate<Class<?>> isCallFromSubclassConstructor = StackWalkerChecker.orFallback();
-        Predicate<Class<?>> isMockConstruction =
-                type -> {
-                    if (isSuspended.get()) {
-                        return false;
-                    } else if ((currentMocking.get() != null
-                                    && type.isAssignableFrom(currentMocking.get()))
-                            || currentConstruction.get() != null) {
-                        return true;
-                    }
-                    Map<Class<?>, ?> interceptors = mockedConstruction.get();
-                    if (interceptors != null && interceptors.containsKey(type)) {
-                        // We only initiate a construction mock, if the call originates from an
-                        // un-mocked (as suppression is not enabled) subclass constructor.
-                        if (isCallFromSubclassConstructor.test(type)) {
-                            return false;
-                        }
-                        currentConstruction.set(type);
-                        return true;
-                    } else {
-                        return false;
-                    }
-                };
-        ConstructionCallback onConstruction =
-                (type, object, arguments, parameterTypeNames) -> {
-                    if (currentMocking.get() != null) {
-                        Object spy = currentSpied.get();
-                        if (spy == null) {
-                            return null;
-                        } else if (type.isInstance(spy)) {
-                            return spy;
-                        } else {
-                            isSuspended.set(true);
-                            try {
-                                // Unexpected construction of non-spied object
-                                throw new MockitoException(
-                                        "Unexpected spy for "
-                                                + type.getName()
-                                                + " on instance of "
-                                                + object.getClass().getName(),
-                                        object instanceof Throwable ? (Throwable) object : null);
-                            } finally {
-                                isSuspended.set(false);
-                            }
-                        }
-                    } else if (currentConstruction.get() != type) {
-                        return null;
-                    }
-                    currentConstruction.remove();
-                    isSuspended.set(true);
-                    try {
-                        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
-                                mockedConstruction.get();
-                        if (interceptors != null) {
-                            BiConsumer<Object, MockedConstruction.Context> interceptor =
-                                    interceptors.get(type);
-                            if (interceptor != null) {
-                                interceptor.accept(
-                                        object,
-                                        new InlineConstructionMockContext(
-                                                arguments, object.getClass(), parameterTypeNames));
-                            }
-                        }
-                    } finally {
-                        isSuspended.set(false);
-                    }
-                    return null;
-                };
-
-        bytecodeGenerator =
-                new TypeCachingBytecodeGenerator(
-                        new InlineBytecodeGenerator(
-                                INSTRUMENTATION,
-                                mocks,
-                                mockedStatics,
-                                isMockConstruction,
-                                onConstruction),
-                        true);
-    }
-
-    @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return doCreateMock(settings, handler, false);
-    }
+    private static class InlineStaticMockController<T> implements StaticMockControl<T> {
 
-    @Override
-    public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T object) {
-        if (object == null) {
-            throw new MockitoConfigurationException("Spy instance must not be null");
-        }
-        currentSpied.set(object);
-        try {
-            return Optional.ofNullable(doCreateMock(settings, handler, true));
-        } finally {
-            currentSpied.remove();
-        }
-    }
+        private final Class<T> targetClass;
 
-    private <T> T doCreateMock(
-            MockCreationSettings<T> settings,
-            MockHandler handler,
-            boolean nullOnNonInlineConstruction) {
-        Class<? extends T> type = createMockType(settings);
+        private final Map<Class<?>, MockMethodInterceptor> interceptorRegistry;
 
-        try {
-            T instance;
-            if (settings.isUsingConstructor()) {
-                instance =
-                        new ConstructorInstantiator(
-                                        settings.getOuterClassInstance() != null,
-                                        settings.getConstructorArgs())
-                                .newInstance(type);
-            } else {
-                try {
-                    // We attempt to use the "native" mock maker first that avoids
-                    // Objenesis and Unsafe
-                    instance = newInstance(type);
-                } catch (InstantiationException ignored) {
-                    if (nullOnNonInlineConstruction) {
-                        return null;
-                    }
-                    Instantiator instantiator =
-                            Plugins.getInstantiatorProvider().getInstantiator(settings);
-                    instance = instantiator.newInstance(type);
-                }
-            }
-            MockMethodInterceptor mockMethodInterceptor =
-                    new MockMethodInterceptor(handler, settings);
-            mocks.put(instance, mockMethodInterceptor);
-            if (instance instanceof MockAccess) {
-                ((MockAccess) instance).setMockitoInterceptor(mockMethodInterceptor);
-            }
-            mocks.expungeStaleEntries();
-            return instance;
-        } catch (InstantiationException e) {
-            throw new MockitoException(
-                    "Unable to create mock instance of type '" + type.getSimpleName() + "'", e);
-        }
-    }
+        private final MockCreationSettings<T> creationConfig;
 
-    @Override
-    public <T> Class<? extends T> createMockType(MockCreationSettings<T> settings) {
-        try {
-            return bytecodeGenerator.mockClass(
-                    MockFeatures.withMockFeatures(
-                            settings.getTypeToMock(),
-                            settings.getExtraInterfaces(),
-                            settings.getSerializableMode(),
-                            settings.isStripAnnotations(),
-                            settings.getDefaultAnswer()));
-        } catch (Exception bytecodeGenerationFailed) {
-            throw prettifyFailure(settings, bytecodeGenerationFailed);
-        }
-    }
-
-    private <T> RuntimeException prettifyFailure(
-            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
-        if (mockFeatures.getTypeToMock().isArray()) {
-            throw new MockitoException(
-                    join("Arrays cannot be mocked: " + mockFeatures.getTypeToMock() + ".", ""),
-                    generationFailed);
-        }
-        if (Modifier.isFinal(mockFeatures.getTypeToMock().getModifiers())) {
-            throw new MockitoException(
-                    join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
-                            "Can not mock final classes with the following settings :",
-                            " - explicit serialization (e.g. withSettings().serializable())",
-                            " - extra interfaces (e.g. withSettings().extraInterfaces(...))",
-                            "",
-                            "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
-                            "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
-                            "",
-                            "Underlying exception : " + generationFailed),
-                    generationFailed);
-        }
-        if (Modifier.isPrivate(mockFeatures.getTypeToMock().getModifiers())) {
-            throw new MockitoException(
-                    join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
-                            "Most likely it is a private class that is not visible by Mockito",
-                            "",
-                            "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
-                            "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
-                            ""),
-                    generationFailed);
-        }
-        throw new MockitoException(
-                join(
-                        "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
-                        "",
-                        "If you're not sure why you're getting this error, please open an issue on GitHub.",
-                        "",
-                        Platform.warnForVM(
-                                "IBM J9 VM",
-                                "Early IBM virtual machine are known to have issues with Mockito, please upgrade to an up-to-date version.\n",
-                                "Hotspot",
-                                ""),
-                        Platform.describe(),
-                        "",
-                        "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
-                        "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
-                        "",
-                        "Underlying exception : " + generationFailed),
-                generationFailed);
-    }
-
-    @Override
-    public MockHandler getHandler(Object mock) {
-        MockMethodInterceptor interceptor;
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            interceptor = interceptors != null ? interceptors.get(mock) : null;
-        } else {
-            interceptor = mocks.get(mock);
-        }
-        if (interceptor == null) {
-            return null;
-        } else {
-            return interceptor.handler;
-        }
-    }
-
-    @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
-        MockMethodInterceptor mockMethodInterceptor =
-                new MockMethodInterceptor(newHandler, settings);
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            if (interceptors == null || !interceptors.containsKey(mock)) {
-                throw new MockitoException(
-                        "Cannot reset "
-                                + mock
-                                + " which is not currently registered as a static mock");
-            }
-            interceptors.put((Class<?>) mock, mockMethodInterceptor);
-        } else {
-            if (!mocks.containsKey(mock)) {
-                throw new MockitoException(
-                        "Cannot reset " + mock + " which is not currently registered as a mock");
-            }
-            mocks.put(mock, mockMethodInterceptor);
-            if (mock instanceof MockAccess) {
-                ((MockAccess) mock).setMockitoInterceptor(mockMethodInterceptor);
-            }
-            mocks.expungeStaleEntries();
-        }
-    }
-
-    @Override
-    public void clearAllCaches() {
-        clearAllMocks();
-        bytecodeGenerator.clearAllCaches();
-    }
-
-    @Override
-    public void clearMock(Object mock) {
-        if (mock instanceof Class<?>) {
-            for (Map<Class<?>, ?> entry : mockedStatics.getBackingMap().target.values()) {
-                entry.remove(mock);
-            }
-        } else {
-            mocks.remove(mock);
-        }
-    }
-
-    @Override
-    public void clearAllMocks() {
-        mockedStatics.getBackingMap().clear();
-        mocks.clear();
-    }
-
-    @Override
-    public TypeMockability isTypeMockable(final Class<?> type) {
-        return new TypeMockability() {
-            @Override
-            public boolean mockable() {
-                return INSTRUMENTATION.isModifiableClass(type) && !EXCLUDES.contains(type);
-            }
-
-            @Override
-            public String nonMockableReason() {
-                if (mockable()) {
-                    return "";
-                }
-                if (type.isPrimitive()) {
-                    return "primitive type";
-                }
-                if (EXCLUDES.contains(type)) {
-                    return "Cannot mock wrapper types, String.class or Class.class";
-                }
-                return "VM does not support modification of given type";
-            }
-        };
-    }
-
-    @Override
-    public <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
-        if (type == ConcurrentHashMap.class) {
-            throw new MockitoException(
-                    "It is not possible to mock static methods of ConcurrentHashMap "
-                            + "to avoid infinitive loops within Mockito's implementation of static mock handling");
-        } else if (type == Thread.class
-                || type == System.class
-                || type == Arrays.class
-                || ClassLoader.class.isAssignableFrom(type)) {
-            throw new MockitoException(
-                    "It is not possible to mock static methods of "
-                            + type.getName()
-                            + " to avoid interfering with class loading what leads to infinite loops");
-        }
-
-        bytecodeGenerator.mockClassStatic(type);
-
-        Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedStatics.set(interceptors);
-        }
-        mockedStatics.getBackingMap().expungeStaleEntries();
-
-        return new InlineStaticMockControl<>(type, interceptors, settings, handler);
-    }
-
-    @Override
-    public <T> ConstructionMockControl<T> createConstructionMock(
-            Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
-            Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
-            MockedConstruction.MockInitializer<T> mockInitializer) {
-        if (type == Object.class) {
-            throw new MockitoException(
-                    "It is not possible to mock construction of the Object class "
-                            + "to avoid inference with default object constructor chains");
-        } else if (type.isPrimitive() || Modifier.isAbstract(type.getModifiers())) {
-            throw new MockitoException(
-                    "It is not possible to construct primitive types or abstract types: "
-                            + type.getName());
-        }
-
-        bytecodeGenerator.mockClassConstruction(type);
-
-        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
-                mockedConstruction.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedConstruction.set(interceptors);
-        }
-        mockedConstruction.getBackingMap().expungeStaleEntries();
-
-        return new InlineConstructionMockControl<>(
-                type, settingsFactory, handlerFactory, mockInitializer, interceptors);
-    }
-
-    @Override
-    @SuppressWarnings("unchecked")
-    public <T> T newInstance(Class<T> cls) throws InstantiationException {
-        Constructor<?>[] constructors = cls.getDeclaredConstructors();
-        if (constructors.length == 0) {
-            throw new InstantiationException(cls.getName() + " does not define a constructor");
-        }
-        Constructor<?> selected = constructors[0];
-        for (Constructor<?> constructor : constructors) {
-            if (Modifier.isPublic(constructor.getModifiers())) {
-                selected = constructor;
-                break;
-            }
-        }
-        Class<?>[] types = selected.getParameterTypes();
-        Object[] arguments = new Object[types.length];
-        int index = 0;
-        for (Class<?> type : types) {
-            arguments[index++] = makeStandardArgument(type);
-        }
-        MemberAccessor accessor = Plugins.getMemberAccessor();
-        try {
-            return (T)
-                    accessor.newInstance(
-                            selected,
-                            callback -> {
-                                currentMocking.set(cls);
-                                try {
-                                    return callback.newInstance();
-                                } finally {
-                                    currentMocking.remove();
-                                }
-                            },
-                            arguments);
-        } catch (Exception e) {
-            throw new InstantiationException("Could not instantiate " + cls.getName(), e);
-        }
-    }
-
-    private Object makeStandardArgument(Class<?> type) {
-        if (type == boolean.class) {
-            return false;
-        } else if (type == byte.class) {
-            return (byte) 0;
-        } else if (type == short.class) {
-            return (short) 0;
-        } else if (type == char.class) {
-            return (char) 0;
-        } else if (type == int.class) {
-            return 0;
-        } else if (type == long.class) {
-            return 0L;
-        } else if (type == float.class) {
-            return 0f;
-        } else if (type == double.class) {
-            return 0d;
-        } else {
-            return null;
-        }
-    }
-
-    private static class InlineStaticMockControl<T> implements StaticMockControl<T> {
-
-        private final Class<T> type;
-
-        private final Map<Class<?>, MockMethodInterceptor> interceptors;
-
-        private final MockCreationSettings<T> settings;
-
-        private final MockHandler handler;
-
-        private InlineStaticMockControl(
-                Class<T> type,
-                Map<Class<?>, MockMethodInterceptor> interceptors,
-                MockCreationSettings<T> settings,
-                MockHandler handler) {
-            this.type = type;
-            this.interceptors = interceptors;
-            this.settings = settings;
-            this.handler = handler;
-        }
+        private final MockHandler mockDelegate;
 
         @Override
         public Class<T> getType() {
-            return type;
+            return targetClass;
         }
 
         @Override
         public void enable() {
-            if (interceptors.putIfAbsent(type, new MockMethodInterceptor(handler, settings))
+            if (interceptorRegistry.putIfAbsent(targetClass, new MockMethodInterceptor(mockDelegate, creationConfig))
                     != null) {
                 throw new MockitoException(
                         join(
                                 "For "
-                                        + type.getName()
+                                        + targetClass.getName()
                                         + ", static mocking is already registered in the current thread",
                                 "",
                                 "To create a new mock, the existing static mock registration must be deregistered"));
@@ -726,79 +253,83 @@ class InlineDelegateByteBuddyMockMaker
 
         @Override
         public void disable() {
-            if (interceptors.remove(type) == null) {
+            if (interceptorRegistry.remove(targetClass) == null) {
                 throw new MockitoException(
                         join(
                                 "Could not deregister "
-                                        + type.getName()
+                                        + targetClass.getName()
                                         + " as a static mock since it is not currently registered",
                                 "",
                                 "To register a static mock, use Mockito.mockStatic("
-                                        + type.getSimpleName()
+                                        + targetClass.getSimpleName()
                                         + ".class)"));
             }
         }
+
+        private InlineStaticMockController(
+                Class<T> targetClass,
+                Map<Class<?>, MockMethodInterceptor> interceptorRegistry,
+                MockCreationSettings<T> creationConfig,
+                MockHandler mockDelegate) {
+            this.targetClass = targetClass;
+            this.interceptorRegistry = interceptorRegistry;
+            this.creationConfig = creationConfig;
+            this.mockDelegate = mockDelegate;
+        }
     }
 
-    private class InlineConstructionMockControl<T> implements ConstructionMockControl<T> {
+    private class InlineConstructionMockController<T> implements ConstructionMockControl<T> {
 
-        private final Class<T> type;
+        private final Class<T> targetClass;
 
-        private final Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory;
-        private final Function<MockedConstruction.Context, MockHandler<T>> handlerFactory;
+        private final Function<MockedConstruction.Context, MockCreationSettings<T>> creationSettingsProvider;
+        private final Function<MockedConstruction.Context, MockHandler<T>> handlerProvider;
 
-        private final MockedConstruction.MockInitializer<T> mockInitializer;
+        private final MockedConstruction.MockInitializer<T> initializerDelegate;
 
-        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors;
+        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorRegistry;
 
-        private final List<Object> all = new ArrayList<>();
-        private int count;
+        private final List<Object> allArgsList = new ArrayList<>();
+        private int total;
 
-        private InlineConstructionMockControl(
-                Class<T> type,
-                Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
-                Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
-                MockedConstruction.MockInitializer<T> mockInitializer,
-                Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors) {
-            this.type = type;
-            this.settingsFactory = settingsFactory;
-            this.handlerFactory = handlerFactory;
-            this.mockInitializer = mockInitializer;
-            this.interceptors = interceptors;
+        @Override
+        public Class<T> getType() {
+            return targetClass;
         }
 
         @Override
-        public Class<T> getType() {
-            return type;
+        @SuppressWarnings("unchecked")
+        public List<T> getMocks() {
+            return (List<T>) allArgsList;
         }
 
         @Override
         public void enable() {
-            if (interceptors.putIfAbsent(
-                            type,
-                            (object, context) -> {
-                                ((InlineConstructionMockContext) context).count = ++count;
-                                MockMethodInterceptor interceptor =
+            if (interceptorRegistry.putIfAbsent(
+                targetClass,
+                            (target, invocationContext) -> {
+                                ((InlineConstructorMockContext) invocationContext).total = ++total;
+                                MockMethodInterceptor constructorInterceptor =
                                         new MockMethodInterceptor(
-                                                handlerFactory.apply(context),
-                                                settingsFactory.apply(context));
-                                mocks.put(object, interceptor);
+                                                handlerProvider.apply(invocationContext),
+                                                creationSettingsProvider.apply(invocationContext));
+                                interceptorMap.put(target, constructorInterceptor);
                                 try {
                                     @SuppressWarnings("unchecked")
-                                    T cast = (T) object;
-                                    mockInitializer.prepare(cast, context);
-                                } catch (Throwable t) {
-                                    mocks.remove(object); // TODO: filter stack trace?
+                                    T castedInstance = (T) target;
+                                    initializerDelegate.prepare(castedInstance, invocationContext);
+                                } catch (Throwable throwable) {
+                                    interceptorMap.remove(target); // TODO: filter stack trace?
                                     throw new MockitoException(
-                                            "Could not initialize mocked construction", t);
+                                            "Could not initialize mocked construction", throwable);
                                 }
-                                all.add(object);
+                                allArgsList.add(target);
                             })
                     != null) {
                 throw new MockitoException(
                         join(
                                 "For "
-                                        + type.getName()
+                                        + targetClass.getName()
                                         + ", static mocking is already registered in the current thread",
                                 "",
                                 "To create a new mock, the existing static mock registration must be deregistered"));
@@ -807,99 +338,563 @@ class InlineDelegateByteBuddyMockMaker
 
         @Override
         public void disable() {
-            if (interceptors.remove(type) == null) {
+            if (interceptorRegistry.remove(targetClass) == null) {
                 throw new MockitoException(
                         join(
                                 "Could not deregister "
-                                        + type.getName()
+                                        + targetClass.getName()
                                         + " as a static mock since it is not currently registered",
                                 "",
                                 "To register a static mock, use Mockito.mockStatic("
-                                        + type.getSimpleName()
+                                        + targetClass.getSimpleName()
                                         + ".class)"));
             }
-            all.clear();
+            allArgsList.clear();
         }
 
-        @Override
-        @SuppressWarnings("unchecked")
-        public List<T> getMocks() {
-            return (List<T>) all;
+        private InlineConstructionMockController(
+                Class<T> targetClass,
+                Function<MockedConstruction.Context, MockCreationSettings<T>> creationSettingsProvider,
+                Function<MockedConstruction.Context, MockHandler<T>> handlerProvider,
+                MockedConstruction.MockInitializer<T> initializerDelegate,
+                Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorRegistry) {
+            this.targetClass = targetClass;
+            this.creationSettingsProvider = creationSettingsProvider;
+            this.handlerProvider = handlerProvider;
+            this.initializerDelegate = initializerDelegate;
+            this.interceptorRegistry = interceptorRegistry;
         }
     }
 
-    private static class InlineConstructionMockContext implements MockedConstruction.Context {
+    private static class InlineConstructorMockContext implements MockedConstruction.Context {
 
-        private static final Map<String, Class<?>> PRIMITIVES = new HashMap<>();
+        private static final Map<String, Class<?>> PRIMITIVE_TYPE_MAP = new HashMap<>();
 
         static {
-            PRIMITIVES.put(boolean.class.getName(), boolean.class);
-            PRIMITIVES.put(byte.class.getName(), byte.class);
-            PRIMITIVES.put(short.class.getName(), short.class);
-            PRIMITIVES.put(char.class.getName(), char.class);
-            PRIMITIVES.put(int.class.getName(), int.class);
-            PRIMITIVES.put(long.class.getName(), long.class);
-            PRIMITIVES.put(float.class.getName(), float.class);
-            PRIMITIVES.put(double.class.getName(), double.class);
+            PRIMITIVE_TYPE_MAP.put(boolean.class.getName(), boolean.class);
+            PRIMITIVE_TYPE_MAP.put(byte.class.getName(), byte.class);
+            PRIMITIVE_TYPE_MAP.put(short.class.getName(), short.class);
+            PRIMITIVE_TYPE_MAP.put(char.class.getName(), char.class);
+            PRIMITIVE_TYPE_MAP.put(int.class.getName(), int.class);
+            PRIMITIVE_TYPE_MAP.put(long.class.getName(), long.class);
+            PRIMITIVE_TYPE_MAP.put(float.class.getName(), float.class);
+            PRIMITIVE_TYPE_MAP.put(double.class.getName(), double.class);
         }
 
-        private int count;
+        private int total;
 
-        private final Object[] arguments;
-        private final Class<?> type;
-        private final String[] parameterTypeNames;
-
-        private InlineConstructionMockContext(
-                Object[] arguments, Class<?> type, String[] parameterTypeNames) {
-            this.arguments = arguments;
-            this.type = type;
-            this.parameterTypeNames = parameterTypeNames;
-        }
+        private final Object[] args;
+        private final Class<?> targetClass;
+        private final String[] paramTypeNames;
 
         @Override
         public int getCount() {
-            if (count == 0) {
+            if (total == 0) {
                 throw new MockitoConfigurationException(
                         "mocked construction context is not initialized");
             }
-            return count;
+            return total;
         }
 
         @Override
         public Constructor<?> constructor() {
-            Class<?>[] parameterTypes = new Class<?>[parameterTypeNames.length];
-            int index = 0;
-            for (String parameterTypeName : parameterTypeNames) {
-                if (PRIMITIVES.containsKey(parameterTypeName)) {
-                    parameterTypes[index++] = PRIMITIVES.get(parameterTypeName);
+            Class<?>[] classArray = new Class<?>[paramTypeNames.length];
+            int idx = 0;
+            for (String typeName : paramTypeNames) {
+                if (PRIMITIVE_TYPE_MAP.containsKey(typeName)) {
+                    classArray[idx++] = PRIMITIVE_TYPE_MAP.get(typeName);
                 } else {
                     try {
-                        parameterTypes[index++] =
-                                Class.forName(parameterTypeName, false, type.getClassLoader());
-                    } catch (ClassNotFoundException e) {
+                        classArray[idx++] =
+                                Class.forName(typeName, false, targetClass.getClassLoader());
+                    } catch (ClassNotFoundException ex) {
                         throw new MockitoException(
-                                "Could not find parameter of type " + parameterTypeName, e);
+                                "Could not find parameter of type " + typeName, ex);
                     }
                 }
             }
             try {
-                return type.getDeclaredConstructor(parameterTypes);
-            } catch (NoSuchMethodException e) {
+                return targetClass.getDeclaredConstructor(classArray);
+            } catch (NoSuchMethodException ex) {
                 throw new MockitoException(
                         join(
                                 "Could not resolve constructor of type",
                                 "",
-                                type.getName(),
+                                targetClass.getName(),
                                 "",
                                 "with arguments of types",
-                                Arrays.toString(parameterTypes)),
-                        e);
+                                Arrays.toString(classArray)),
+                    ex);
             }
         }
 
         @Override
         public List<?> arguments() {
-            return Collections.unmodifiableList(Arrays.asList(arguments));
+            return Collections.unmodifiableList(Arrays.asList(args));
+        }
+
+        private InlineConstructorMockContext(
+            Object[] args, Class<?> targetClass, String[] paramTypeNames) {
+            this.args = args;
+            this.targetClass = targetClass;
+            this.paramTypeNames = paramTypeNames;
+        }
+    }
+
+    public void resetMockInterceptor(Object subject, MockHandler replacementHandler, MockCreationSettings creationConfig) {
+        MockMethodInterceptor methodInterceptor =
+                new MockMethodInterceptor(replacementHandler, creationConfig);
+        if (subject instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptorRegistry = staticInterceptorLocal.get();
+            if (interceptorRegistry == null || !interceptorRegistry.containsKey(subject)) {
+                throw new MockitoException(
+                        "Cannot reset "
+                                + subject
+                                + " which is not currently registered as a static mock");
+            }
+            interceptorRegistry.put((Class<?>) subject, methodInterceptor);
+        } else {
+            if (!interceptorMap.containsKey(subject)) {
+                throw new MockitoException(
+                        "Cannot reset " + subject + " which is not currently registered as a mock");
+            }
+            interceptorMap.put(subject, methodInterceptor);
+            if (subject instanceof MockAccess) {
+                ((MockAccess) subject).setMockitoInterceptor(methodInterceptor);
+            }
+            interceptorMap.expungeStaleEntries();
+        }
+    }
+
+    @Override
+    @SuppressWarnings("unchecked")
+    public <T> T newInstance(Class<T> targetClass) throws InstantiationException {
+        Constructor<?>[] declaredConstructors = targetClass.getDeclaredConstructors();
+        if (declaredConstructors.length == 0) {
+            throw new InstantiationException(targetClass.getName() + " does not define a constructor");
+        }
+        Constructor<?> chosenConstructor = declaredConstructors[0];
+        for (Constructor<?> targetCtor : declaredConstructors) {
+            if (Modifier.isPublic(targetCtor.getModifiers())) {
+                chosenConstructor = targetCtor;
+                break;
+            }
+        }
+        Class<?>[] parameterTypes = chosenConstructor.getParameterTypes();
+        Object[] args = new Object[parameterTypes.length];
+        int idx = 0;
+        for (Class<?> type : parameterTypes) {
+            args[idx++] = makeDefaultArgument(type);
+        }
+        MemberAccessor memberHandler = Plugins.getMemberAccessor();
+        try {
+            return (T)
+                    memberHandler.newInstance(
+                        chosenConstructor,
+                        creationDispatcher -> {
+                                mockingTarget.set(targetClass);
+                                try {
+                                    return creationDispatcher.newInstance();
+                                } finally {
+                                    mockingTarget.remove();
+                                }
+                            },
+                        args);
+        } catch (Exception ex) {
+            throw new InstantiationException("Could not instantiate " + targetClass.getName(), ex);
+        }
+    }
+
+    private Object makeDefaultArgument(Class<?> targetClass) {
+        if (targetClass == boolean.class) {
+            return false;
+        } else if (targetClass == byte.class) {
+            return (byte) 0;
+        } else if (targetClass == short.class) {
+            return (short) 0;
+        } else if (targetClass == char.class) {
+            return (char) 0;
+        } else if (targetClass == int.class) {
+            return 0;
+        } else if (targetClass == long.class) {
+            return 0L;
+        } else if (targetClass == float.class) {
+            return 0f;
+        } else if (targetClass == double.class) {
+            return 0d;
+        } else {
+            return null;
+        }
+    }
+
+    @Override
+    public TypeMockability isTypeMockable(final Class<?> targetClass) {
+        return new TypeMockability() {
+
+            @Override
+            public String nonMockableReason() {
+                if (mockable()) {
+                    return "";
+                }
+                if (targetClass.isPrimitive()) {
+                    return "primitive type";
+                }
+                if (EXCLUDES.contains(targetClass)) {
+                    return "Cannot mock wrapper types, String.class or Class.class";
+                }
+                return "VM does not support modification of given type";
+            }
+
+            @Override
+            public boolean mockable() {
+                return JVM_AGENT.isModifiableClass(targetClass) && !EXCLUDES.contains(targetClass);
+            }
+        };
+    }
+
+    @Override
+    public MockHandler getHandler(Object subject) {
+        MockMethodInterceptor constructorInterceptor;
+        if (subject instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptorRegistry = staticInterceptorLocal.get();
+            constructorInterceptor = interceptorRegistry != null ? interceptorRegistry.get(subject) : null;
+        } else {
+            constructorInterceptor = interceptorMap.get(subject);
+        }
+        if (constructorInterceptor == null) {
+            return null;
+        } else {
+            return constructorInterceptor.handler;
+        }
+    }
+
+    private <T> RuntimeException formatFailureMessage(
+        MockCreationSettings<T> featuresSettings, Exception generationException) {
+        if (featuresSettings.getTypeToMock().isArray()) {
+            throw new MockitoException(
+                    join("Arrays cannot be mocked: " + featuresSettings.getTypeToMock() + ".", ""),
+                generationException);
+        }
+        if (Modifier.isFinal(featuresSettings.getTypeToMock().getModifiers())) {
+            throw new MockitoException(
+                    join(
+                            "Mockito cannot mock this class: " + featuresSettings.getTypeToMock() + ".",
+                            "Can not mock final classes with the following settings :",
+                            " - explicit serialization (e.g. withSettings().serializable())",
+                            " - extra interfaces (e.g. withSettings().extraInterfaces(...))",
+                            "",
+                            "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
+                            "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
+                            "",
+                            "Underlying exception : " + generationException),
+                generationException);
+        }
+        if (Modifier.isPrivate(featuresSettings.getTypeToMock().getModifiers())) {
+            throw new MockitoException(
+                    join(
+                            "Mockito cannot mock this class: " + featuresSettings.getTypeToMock() + ".",
+                            "Most likely it is a private class that is not visible by Mockito",
+                            "",
+                            "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
+                            "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
+                            ""),
+                generationException);
+        }
+        throw new MockitoException(
+                join(
+                        "Mockito cannot mock this class: " + featuresSettings.getTypeToMock() + ".",
+                        "",
+                        "If you're not sure why you're getting this error, please open an issue on GitHub.",
+                        "",
+                        Platform.warnForVM(
+                                "IBM J9 VM",
+                                "Early IBM virtual machine are known to have issues with Mockito, please upgrade to an up-to-date version.\n",
+                                "Hotspot",
+                                ""),
+                        Platform.describe(),
+                        "",
+                        "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
+                        "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
+                        "",
+                        "Underlying exception : " + generationException),
+            generationException);
+    }
+
+    public <T> StaticMockControl<T> createStaticMockController(
+        Class<T> targetClass, MockCreationSettings<T> creationConfig, MockHandler mockDelegate) {
+        if (targetClass == ConcurrentHashMap.class) {
+            throw new MockitoException(
+                    "It is not possible to mock static methods of ConcurrentHashMap "
+                            + "to avoid infinitive loops within Mockito's implementation of static mock handling");
+        } else if (targetClass == Thread.class
+                || targetClass == System.class
+                || targetClass == Arrays.class
+                || ClassLoader.class.isAssignableFrom(targetClass)) {
+            throw new MockitoException(
+                    "It is not possible to mock static methods of "
+                            + targetClass.getName()
+                            + " to avoid interfering with class loading what leads to infinite loops");
+        }
+
+        classGenerator.mockClassStatic(targetClass);
+
+        Map<Class<?>, MockMethodInterceptor> interceptorRegistry = staticInterceptorLocal.get();
+        if (interceptorRegistry == null) {
+            interceptorRegistry = new WeakHashMap<>();
+            staticInterceptorLocal.set(interceptorRegistry);
+        }
+        staticInterceptorLocal.getBackingMap().expungeStaleEntries();
+
+        return new InlineStaticMockController<>(targetClass, interceptorRegistry, creationConfig, mockDelegate);
+    }
+
+    public <T> Optional<T> createSpyInstance(
+        MockCreationSettings<T> creationConfig, MockHandler mockDelegate, T target) {
+        if (target == null) {
+            throw new MockitoConfigurationException("Spy instance must not be null");
+        }
+        spiedInstanceHolder.set(target);
+        try {
+            return Optional.ofNullable(createMockInstance(creationConfig, mockDelegate, true));
+        } finally {
+            spiedInstanceHolder.remove();
+        }
+    }
+
+    @Override
+    public <T> Class<? extends T> createMockType(MockCreationSettings<T> creationConfig) {
+        try {
+            return classGenerator.mockClass(
+                    MockFeatures.withMockFeatures(
+                            creationConfig.getTypeToMock(),
+                            creationConfig.getExtraInterfaces(),
+                            creationConfig.getSerializableMode(),
+                            creationConfig.isStripAnnotations(),
+                            creationConfig.getDefaultAnswer()));
+        } catch (Exception generationException) {
+            throw formatFailureMessage(creationConfig, generationException);
         }
     }
+
+    public <T> T createMockInstance(MockCreationSettings<T> creationConfig, MockHandler mockDelegate) {
+        return createMockInstance(creationConfig, mockDelegate, false);
+    }
+
+    private <T> T createMockInstance(
+            MockCreationSettings<T> creationConfig,
+            MockHandler mockDelegate,
+            boolean nullOnNonInline) {
+        Class<? extends T> targetClass = createMockType(creationConfig);
+
+        try {
+            T createdInstance;
+            if (creationConfig.isUsingConstructor()) {
+                createdInstance =
+                        new ConstructorInstantiator(
+                                        creationConfig.getOuterClassInstance() != null,
+                                        creationConfig.getConstructorArgs())
+                                .newInstance(targetClass);
+            } else {
+                try {
+                    // We attempt to use the "native" mock maker first that avoids
+                    // Objenesis and Unsafe
+                    createdInstance = newInstance(targetClass);
+                } catch (InstantiationException suppressedError) {
+                    if (nullOnNonInline) {
+                        return null;
+                    }
+                    Instantiator objectInstantiator =
+                            Plugins.getInstantiatorProvider().getInstantiator(creationConfig);
+                    createdInstance = objectInstantiator.newInstance(targetClass);
+                }
+            }
+            MockMethodInterceptor methodInterceptor =
+                    new MockMethodInterceptor(mockDelegate, creationConfig);
+            interceptorMap.put(createdInstance, methodInterceptor);
+            if (createdInstance instanceof MockAccess) {
+                ((MockAccess) createdInstance).setMockitoInterceptor(methodInterceptor);
+            }
+            interceptorMap.expungeStaleEntries();
+            return createdInstance;
+        } catch (InstantiationException ex) {
+            throw new MockitoException(
+                    "Unable to create mock instance of type '" + targetClass.getSimpleName() + "'", ex);
+        }
+    }
+
+    public <T> ConstructionMockControl<T> createConstructionMockController(
+            Class<T> targetClass,
+            Function<MockedConstruction.Context, MockCreationSettings<T>> creationSettingsProvider,
+            Function<MockedConstruction.Context, MockHandler<T>> handlerProvider,
+            MockedConstruction.MockInitializer<T> initializerDelegate) {
+        if (targetClass == Object.class) {
+            throw new MockitoException(
+                    "It is not possible to mock construction of the Object class "
+                            + "to avoid inference with default object constructor chains");
+        } else if (targetClass.isPrimitive() || Modifier.isAbstract(targetClass.getModifiers())) {
+            throw new MockitoException(
+                    "It is not possible to construct primitive types or abstract types: "
+                            + targetClass.getName());
+        }
+
+        classGenerator.mockClassConstruction(targetClass);
+
+        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorRegistry =
+                constructionCallbacksLocal.get();
+        if (interceptorRegistry == null) {
+            interceptorRegistry = new WeakHashMap<>();
+            constructionCallbacksLocal.set(interceptorRegistry);
+        }
+        constructionCallbacksLocal.getBackingMap().expungeStaleEntries();
+
+        return new InlineConstructionMockController<>(
+            targetClass, creationSettingsProvider, handlerProvider, initializerDelegate, interceptorRegistry);
+    }
+
+    @Override
+    public void clearMock(Object subject) {
+        if (subject instanceof Class<?>) {
+            for (Map<Class<?>, ?> classToInstanceMap : staticInterceptorLocal.getBackingMap().target.values()) {
+                classToInstanceMap.remove(subject);
+            }
+        } else {
+            interceptorMap.remove(subject);
+        }
+    }
+
+    public void clearCachesAndMocks() {
+        clearAllMocks();
+        classGenerator.clearAllCaches();
+    }
+
+    @Override
+    public void clearAllMocks() {
+        staticInterceptorLocal.getBackingMap().clear();
+        interceptorMap.clear();
+    }
+
+    InlineDelegatingByteBuddyMockFactory() {
+        if (STARTUP_EXCEPTION != null) {
+            String messageDetail;
+            if (PlatformUtils.isAndroidPlatform() || PlatformUtils.isProbablyTermuxEnvironment()) {
+                messageDetail =
+                        "It appears as if you are trying to run this mock maker on Android which does not support the instrumentation API.";
+            } else {
+                try {
+                    if (STARTUP_EXCEPTION instanceof NoClassDefFoundError
+                            && STARTUP_EXCEPTION.getMessage() != null
+                            && STARTUP_EXCEPTION
+                                    .getMessage()
+                                    .startsWith("net/bytebuddy/agent/")) {
+                        messageDetail =
+                                join(
+                                        "It seems like you are running Mockito with an incomplete or inconsistent class path. Byte Buddy Agent could not be loaded.",
+                                        "",
+                                        "Byte Buddy Agent is available on Maven Central as 'net.bytebuddy:byte-buddy-agent' with the module name 'net.bytebuddy.agent'.",
+                                        "Normally, your IDE or build tool (such as Maven or Gradle) should take care of your class path completion but ");
+                    } else if (Class.forName("javax.tools.ToolProvider")
+                                    .getMethod("getSystemJavaCompiler")
+                                    .invoke(null)
+                            == null) {
+                        messageDetail =
+                                "It appears as if you are running on a JRE. Either install a JDK or add JNA to the class path.";
+                    } else {
+                        messageDetail =
+                                "It appears as if your JDK does not supply a working agent attachment mechanism.";
+                    }
+                } catch (Throwable suppressedError) {
+                    messageDetail =
+                            "It appears as if you are running an incomplete JVM installation that might not support all tooling APIs";
+                }
+            }
+            throw new MockitoInitializationException(
+                    join(
+                            "Could not initialize inline Byte Buddy mock maker.",
+                            "",
+                        messageDetail,
+                            Platform.describe()),
+                STARTUP_EXCEPTION);
+        }
+
+        ThreadLocal<Class<?>> constructionTargetLocal = new ThreadLocal<>();
+        ThreadLocal<Boolean> suspendedFlag = ThreadLocal.withInitial(() -> false);
+        Predicate<Class<?>> isFromSubclassCtor = StackWalkerChecker.orFallback();
+        Predicate<Class<?>> mockCtorPredicate =
+            targetClass -> {
+                    if (suspendedFlag.get()) {
+                        return false;
+                    } else if ((mockingTarget.get() != null
+                                    && targetClass.isAssignableFrom(mockingTarget.get()))
+                            || constructionTargetLocal.get() != null) {
+                        return true;
+                    }
+                    Map<Class<?>, ?> interceptorRegistry = constructionCallbacksLocal.get();
+                    if (interceptorRegistry != null && interceptorRegistry.containsKey(targetClass)) {
+                        // We only initiate a construction mock, if the call originates from an
+                        // un-mocked (as suppression is not enabled) subclass constructor.
+                        if (isFromSubclassCtor.test(targetClass)) {
+                            return false;
+                        }
+                        constructionTargetLocal.set(targetClass);
+                        return true;
+                    } else {
+                        return false;
+                    }
+                };
+        ConstructionCallback constructionCallback =
+                (targetClass, target, args, paramTypeNames) -> {
+                    if (mockingTarget.get() != null) {
+                        Object spyInstance = spiedInstanceHolder.get();
+                        if (spyInstance == null) {
+                            return null;
+                        } else if (targetClass.isInstance(spyInstance)) {
+                            return spyInstance;
+                        } else {
+                            suspendedFlag.set(true);
+                            try {
+                                // Unexpected construction of non-spied object
+                                throw new MockitoException(
+                                        "Unexpected spy for "
+                                                + targetClass.getName()
+                                                + " on instance of "
+                                                + target.getClass().getName(),
+                                        target instanceof Throwable ? (Throwable) target : null);
+                            } finally {
+                                suspendedFlag.set(false);
+                            }
+                        }
+                    } else if (constructionTargetLocal.get() != targetClass) {
+                        return null;
+                    }
+                    constructionTargetLocal.remove();
+                    suspendedFlag.set(true);
+                    try {
+                        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorRegistry =
+                                constructionCallbacksLocal.get();
+                        if (interceptorRegistry != null) {
+                            BiConsumer<Object, MockedConstruction.Context> constructorInterceptor =
+                                    interceptorRegistry.get(targetClass);
+                            if (constructorInterceptor != null) {
+                                constructorInterceptor.accept(
+                                    target,
+                                        new InlineConstructorMockContext(
+                                            args, target.getClass(), paramTypeNames));
+                            }
+                        }
+                    } finally {
+                        suspendedFlag.set(false);
+                    }
+                    return null;
+                };
+
+        classGenerator =
+                new TypeCachingBytecodeGenerator(
+                        new InlineBytecodeGenerator(
+                            JVM_AGENT,
+                            interceptorMap,
+                            staticInterceptorLocal,
+                            mockCtorPredicate,
+                            constructionCallback),
+                        true);
+    }
 }
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
index 9069e50b8..54ed3fbd6 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
@@ -14,7 +14,7 @@ import static org.mockito.Mockito.verify;
 
 public class InlineByteBuddyMockMakerTest extends TestBase {
 
-    @Mock private InlineDelegateByteBuddyMockMaker delegate;
+    @Mock private InlineDelegatingByteBuddyMockFactory delegate;
 
     @Test
     public void should_delegate_call() {
@@ -34,15 +34,15 @@ public class InlineByteBuddyMockMakerTest extends TestBase {
         mockMaker.clearAllMocks();
         mockMaker.clearAllCaches();
 
-        verify(delegate).createMock(creationSettings, handler);
-        verify(delegate).createStaticMock(Object.class, creationSettings, handler);
-        verify(delegate).createConstructionMock(Object.class, null, null, null);
+        verify(delegate).createMockInstance(creationSettings, handler);
+        verify(delegate).createStaticMockController(Object.class, creationSettings, handler);
+        verify(delegate).createConstructionMockController(Object.class, null, null, null);
         verify(delegate).createMockType(creationSettings);
         verify(delegate).getHandler(this);
         verify(delegate).isTypeMockable(Object.class);
-        verify(delegate).resetMock(this, handler, creationSettings);
+        verify(delegate).resetMockInterceptor(this, handler, creationSettings);
         verify(delegate).clearMock(this);
         verify(delegate).clearAllMocks();
-        verify(delegate).clearAllCaches();
+        verify(delegate).clearCachesAndMocks();
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

