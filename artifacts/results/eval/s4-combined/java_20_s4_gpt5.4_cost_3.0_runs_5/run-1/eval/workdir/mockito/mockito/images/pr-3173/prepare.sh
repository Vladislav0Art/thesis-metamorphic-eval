#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout bfee15dda7acc41ef497d8f8a44c74dacce2933a

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockFactory.java
similarity index 56%
rename from src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
rename to src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockFactory.java
index 227df4cd1..8632d683a 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockFactory.java
@@ -100,12 +100,12 @@ import static org.mockito.internal.util.StringUtil.join;
  * support this feature.
  */
 @SuppressSignatureCheck
-class InlineDelegateByteBuddyMockMaker
+class InlineByteBuddyMockFactory
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
 
-    private static final Instrumentation INSTRUMENTATION;
+    private static final Instrumentation JAVA_AGENT;
 
-    private static final Throwable INITIALIZATION_ERROR;
+    private static final Throwable STARTUP_EXCEPTION;
 
     static {
         Instrumentation instrumentation;
@@ -145,7 +145,7 @@ class InlineDelegateByteBuddyMockMaker
                     String source =
                             "org/mockito/internal/creation/bytebuddy/inject/MockMethodDispatcher";
                     InputStream inputStream =
-                            InlineDelegateByteBuddyMockMaker.class
+                            InlineByteBuddyMockFactory.class
                                     .getClassLoader()
                                     .getResourceAsStream(source + ".raw");
                     if (inputStream == null) {
@@ -156,7 +156,7 @@ class InlineDelegateByteBuddyMockMaker
                                                 + ".raw",
                                         "",
                                         "The class loader responsible for looking up the resource: "
-                                                + InlineDelegateByteBuddyMockMaker.class
+                                                + InlineByteBuddyMockFactory.class
                                                         .getClassLoader()));
                     }
                     outputStream.putNextEntry(new JarEntry(source + ".class"));
@@ -203,235 +203,382 @@ class InlineDelegateByteBuddyMockMaker
             instrumentation = null;
             initializationError = throwable;
         }
-        INSTRUMENTATION = instrumentation;
-        INITIALIZATION_ERROR = initializationError;
+        JAVA_AGENT = instrumentation;
+        STARTUP_EXCEPTION = initializationError;
     }
 
-    private final BytecodeGenerator bytecodeGenerator;
+    private final BytecodeGenerator classGenerator;
 
-    private final WeakConcurrentMap<Object, MockMethodInterceptor> mocks =
+    private final WeakConcurrentMap<Object, MockMethodInterceptor> proxyMap =
             new WeakConcurrentMap<>(false);
 
-    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> mockedStatics =
+    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> staticInterceptors =
             new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
     private final DetachedThreadLocal<Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>>>
-            mockedConstruction = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
+        constructionInterceptors = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
-    private final ThreadLocal<Boolean> mockitoConstruction = ThreadLocal.withInitial(() -> false);
+    private final ThreadLocal<Boolean> constructionFlag = ThreadLocal.withInitial(() -> false);
 
-    private final ThreadLocal<Object> currentSpied = new ThreadLocal<>();
+    private final ThreadLocal<Object> currentSpy = new ThreadLocal<>();
 
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
+    private static class InlineStaticMockController<T> implements StaticMockControl<T> {
+
+        private final Class<T> targetClass;
+
+        private final Map<Class<?>, MockMethodInterceptor> classHandlerMap;
+
+        private final MockCreationSettings<T> creationConfig;
+
+        private final MockHandler invocationHandler;
+
+        @Override
+        public Class<T> getType() {
+            return targetClass;
+        }
+
+        @Override
+        public void enable() {
+            if (classHandlerMap.putIfAbsent(targetClass, new MockMethodInterceptor(invocationHandler, creationConfig))
+                    != null) {
+                throw new MockitoException(
+                        join(
+                                "For "
+                                        + targetClass.getName()
+                                        + ", static mocking is already registered in the current thread",
+                                "",
+                                "To create a new mock, the existing static mock registration must be deregistered"));
             }
-            throw new MockitoInitializationException(
-                    join(
-                            "Could not initialize inline Byte Buddy mock maker.",
-                            "",
-                            detail,
-                            Platform.describe()),
-                    INITIALIZATION_ERROR);
         }
 
-        ThreadLocal<Class<?>> currentConstruction = new ThreadLocal<>();
-        ThreadLocal<Boolean> isSuspended = ThreadLocal.withInitial(() -> false);
-        Predicate<Class<?>> isCallFromSubclassConstructor = StackWalkerChecker.orFallback();
-        Predicate<Class<?>> isMockConstruction =
-                type -> {
-                    if (isSuspended.get()) {
-                        return false;
-                    } else if (mockitoConstruction.get() || currentConstruction.get() != null) {
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
-                    if (mockitoConstruction.get()) {
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
+        @Override
+        public void disable() {
+            if (classHandlerMap.remove(targetClass) == null) {
+                throw new MockitoException(
+                        join(
+                                "Could not deregister "
+                                        + targetClass.getName()
+                                        + " as a static mock since it is not currently registered",
+                                "",
+                                "To register a static mock, use Mockito.mockStatic("
+                                        + targetClass.getSimpleName()
+                                        + ".class)"));
+            }
+        }
+
+        private InlineStaticMockController(
+                Class<T> targetClass,
+                Map<Class<?>, MockMethodInterceptor> classHandlerMap,
+                MockCreationSettings<T> creationConfig,
+                MockHandler invocationHandler) {
+            this.targetClass = targetClass;
+            this.classHandlerMap = classHandlerMap;
+            this.creationConfig = creationConfig;
+            this.invocationHandler = invocationHandler;
+        }
+    }
+
+    private class InlineConstructionMockController<T> implements ConstructionMockControl<T> {
+
+        private final Class<T> targetClass;
+
+        private final Function<MockedConstruction.Context, MockCreationSettings<T>> creationProvider;
+        private final Function<MockedConstruction.Context, MockHandler<T>> invocationFactory;
+
+        private final MockedConstruction.MockInitializer<T> initRoutine;
+
+        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> classHandlerMap;
+
+        private final List<Object> instances = new ArrayList<>();
+        private int size;
+
+        @Override
+        public Class<T> getType() {
+            return targetClass;
+        }
+
+        @Override
+        @SuppressWarnings("unchecked")
+        public List<T> getMocks() {
+            return (List<T>) instances;
+        }
+
+        @Override
+        public void enable() {
+            if (classHandlerMap.putIfAbsent(
+                targetClass,
+                            (instance, invocationCtx) -> {
+                                ((InlineConstructorMockContext) invocationCtx).size = ++size;
+                                MockMethodInterceptor constructionHandler =
+                                        new MockMethodInterceptor(
+                                                invocationFactory.apply(invocationCtx),
+                                                creationProvider.apply(invocationCtx));
+                                proxyMap.put(instance, constructionHandler);
+                                try {
+                                    @SuppressWarnings("unchecked")
+                                    T typedInstance = (T) instance;
+                                    initRoutine.prepare(typedInstance, invocationCtx);
+                                } catch (Throwable throwable) {
+                                    proxyMap.remove(instance); // TODO: filter stack trace?
+                                    throw new MockitoException(
+                                            "Could not initialize mocked construction", throwable);
+                                }
+                                instances.add(instance);
+                            })
+                    != null) {
+                throw new MockitoException(
+                        join(
+                                "For "
+                                        + targetClass.getName()
+                                        + ", static mocking is already registered in the current thread",
+                                "",
+                                "To create a new mock, the existing static mock registration must be deregistered"));
+            }
+        }
+
+        @Override
+        public void disable() {
+            if (classHandlerMap.remove(targetClass) == null) {
+                throw new MockitoException(
+                        join(
+                                "Could not deregister "
+                                        + targetClass.getName()
+                                        + " as a static mock since it is not currently registered",
+                                "",
+                                "To register a static mock, use Mockito.mockStatic("
+                                        + targetClass.getSimpleName()
+                                        + ".class)"));
+            }
+            instances.clear();
+        }
+
+        private InlineConstructionMockController(
+                Class<T> targetClass,
+                Function<MockedConstruction.Context, MockCreationSettings<T>> creationProvider,
+                Function<MockedConstruction.Context, MockHandler<T>> invocationFactory,
+                MockedConstruction.MockInitializer<T> initRoutine,
+                Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> classHandlerMap) {
+            this.targetClass = targetClass;
+            this.creationProvider = creationProvider;
+            this.invocationFactory = invocationFactory;
+            this.initRoutine = initRoutine;
+            this.classHandlerMap = classHandlerMap;
+        }
+    }
+
+    private static class InlineConstructorMockContext implements MockedConstruction.Context {
+
+        private static final Map<String, Class<?>> PRIMITIVE_TYPES = new HashMap<>();
+
+        static {
+            PRIMITIVE_TYPES.put(boolean.class.getName(), boolean.class);
+            PRIMITIVE_TYPES.put(byte.class.getName(), byte.class);
+            PRIMITIVE_TYPES.put(short.class.getName(), short.class);
+            PRIMITIVE_TYPES.put(char.class.getName(), char.class);
+            PRIMITIVE_TYPES.put(int.class.getName(), int.class);
+            PRIMITIVE_TYPES.put(long.class.getName(), long.class);
+            PRIMITIVE_TYPES.put(float.class.getName(), float.class);
+            PRIMITIVE_TYPES.put(double.class.getName(), double.class);
+        }
+
+        private int size;
+
+        private final Object[] args;
+        private final Class<?> targetClass;
+        private final String[] paramTypeNames;
+
+        @Override
+        public int getCount() {
+            if (size == 0) {
+                throw new MockitoConfigurationException(
+                        "mocked construction context is not initialized");
+            }
+            return size;
+        }
+
+        @Override
+        public Constructor<?> constructor() {
+            Class<?>[] parameterClasses = new Class<?>[paramTypeNames.length];
+            int pos = 0;
+            for (String paramClassName : paramTypeNames) {
+                if (PRIMITIVE_TYPES.containsKey(paramClassName)) {
+                    parameterClasses[pos++] = PRIMITIVE_TYPES.get(paramClassName);
+                } else {
                     try {
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
+                        parameterClasses[pos++] =
+                                Class.forName(paramClassName, false, targetClass.getClassLoader());
+                    } catch (ClassNotFoundException ex) {
+                        throw new MockitoException(
+                                "Could not find parameter of type " + paramClassName, ex);
                     }
-                    return null;
-                };
+                }
+            }
+            try {
+                return targetClass.getDeclaredConstructor(parameterClasses);
+            } catch (NoSuchMethodException ex) {
+                throw new MockitoException(
+                        join(
+                                "Could not resolve constructor of type",
+                                "",
+                                targetClass.getName(),
+                                "",
+                                "with arguments of types",
+                                Arrays.toString(parameterClasses)),
+                    ex);
+            }
+        }
 
-        bytecodeGenerator =
-                new TypeCachingBytecodeGenerator(
-                        new InlineBytecodeGenerator(
-                                INSTRUMENTATION,
-                                mocks,
-                                mockedStatics,
-                                isMockConstruction,
-                                onConstruction),
-                        true);
+        @Override
+        public List<?> arguments() {
+            return Collections.unmodifiableList(Arrays.asList(args));
+        }
+
+        private InlineConstructorMockContext(
+            Object[] args, Class<?> targetClass, String[] paramTypeNames) {
+            this.args = args;
+            this.targetClass = targetClass;
+            this.paramTypeNames = paramTypeNames;
+        }
     }
 
-    @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return doCreateMock(settings, handler, false);
+    public void resetMockInterceptor(Object mockInstance, MockHandler replacementHandler, MockCreationSettings creationConfig) {
+        MockMethodInterceptor methodInterceptor =
+                new MockMethodInterceptor(replacementHandler, creationConfig);
+        if (mockInstance instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> classHandlerMap = staticInterceptors.get();
+            if (classHandlerMap == null || !classHandlerMap.containsKey(mockInstance)) {
+                throw new MockitoException(
+                        "Cannot reset "
+                                + mockInstance
+                                + " which is not currently registered as a static mock");
+            }
+            classHandlerMap.put((Class<?>) mockInstance, methodInterceptor);
+        } else {
+            if (!proxyMap.containsKey(mockInstance)) {
+                throw new MockitoException(
+                        "Cannot reset " + mockInstance + " which is not currently registered as a mock");
+            }
+            proxyMap.put(mockInstance, methodInterceptor);
+            if (mockInstance instanceof MockAccess) {
+                ((MockAccess) mockInstance).setMockitoInterceptor(methodInterceptor);
+            }
+            proxyMap.expungeStaleEntries();
+        }
     }
 
     @Override
-    public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T object) {
-        if (object == null) {
-            throw new MockitoConfigurationException("Spy instance must not be null");
+    @SuppressWarnings("unchecked")
+    public <T> T newInstance(Class<T> targetClass) throws InstantiationException {
+        Constructor<?>[] ctorArray = targetClass.getDeclaredConstructors();
+        if (ctorArray.length == 0) {
+            throw new InstantiationException(targetClass.getName() + " does not define a constructor");
+        }
+        Constructor<?> chosenCtor = ctorArray[0];
+        for (Constructor<?> ctor : ctorArray) {
+            if (Modifier.isPublic(ctor.getModifiers())) {
+                chosenCtor = ctor;
+                break;
+            }
+        }
+        Class<?>[] paramClasses = chosenCtor.getParameterTypes();
+        Object[] args = new Object[paramClasses.length];
+        int pos = 0;
+        for (Class<?> subjectClass : paramClasses) {
+            args[pos++] = makeDefaultArgument(subjectClass);
         }
-        currentSpied.set(object);
+        MemberAccessor memberBridge = Plugins.getMemberAccessor();
         try {
-            return Optional.ofNullable(doCreateMock(settings, handler, true));
-        } finally {
-            currentSpied.remove();
+            return (T)
+                    memberBridge.newInstance(
+                        chosenCtor,
+                        constructionDispatcher -> {
+                                constructionFlag.set(true);
+                                try {
+                                    return constructionDispatcher.newInstance();
+                                } finally {
+                                    constructionFlag.set(false);
+                                }
+                            },
+                        args);
+        } catch (Exception ex) {
+            throw new InstantiationException("Could not instantiate " + targetClass.getName(), ex);
         }
     }
 
-    private <T> T doCreateMock(
-            MockCreationSettings<T> settings,
-            MockHandler handler,
-            boolean nullOnNonInlineConstruction) {
-        Class<? extends T> type = createMockType(settings);
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
                 }
+                if (EXCLUDES.contains(targetClass)) {
+                    return "Cannot mock wrapper types, String.class or Class.class";
+                }
+                return "VM does not support modification of given type";
             }
-            MockMethodInterceptor mockMethodInterceptor =
-                    new MockMethodInterceptor(handler, settings);
-            mocks.put(instance, mockMethodInterceptor);
-            if (instance instanceof MockAccess) {
-                ((MockAccess) instance).setMockitoInterceptor(mockMethodInterceptor);
+
+            @Override
+            public boolean mockable() {
+                return JAVA_AGENT.isModifiableClass(targetClass) && !EXCLUDES.contains(targetClass);
             }
-            mocks.expungeStaleEntries();
-            return instance;
-        } catch (InstantiationException e) {
-            throw new MockitoException(
-                    "Unable to create mock instance of type '" + type.getSimpleName() + "'", e);
-        }
+        };
     }
 
     @Override
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
+    public MockHandler getHandler(Object mockInstance) {
+        MockMethodInterceptor constructionHandler;
+        if (mockInstance instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> classHandlerMap = staticInterceptors.get();
+            constructionHandler = classHandlerMap != null ? classHandlerMap.get(mockInstance) : null;
+        } else {
+            constructionHandler = proxyMap.get(mockInstance);
+        }
+        if (constructionHandler == null) {
+            return null;
+        } else {
+            return constructionHandler.handler;
         }
     }
 
-    private <T> RuntimeException prettifyFailure(
-            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
-        if (mockFeatures.getTypeToMock().isArray()) {
+    private <T> RuntimeException formatFailureMessage(
+        MockCreationSettings<T> creationFeatures, Exception failure) {
+        if (creationFeatures.getTypeToMock().isArray()) {
             throw new MockitoException(
-                    join("Arrays cannot be mocked: " + mockFeatures.getTypeToMock() + ".", ""),
-                    generationFailed);
+                    join("Arrays cannot be mocked: " + creationFeatures.getTypeToMock() + ".", ""),
+                failure);
         }
-        if (Modifier.isFinal(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isFinal(creationFeatures.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + creationFeatures.getTypeToMock() + ".",
                             "Can not mock final classes with the following settings :",
                             " - explicit serialization (e.g. withSettings().serializable())",
                             " - extra interfaces (e.g. withSettings().extraInterfaces(...))",
@@ -439,23 +586,23 @@ class InlineDelegateByteBuddyMockMaker
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             "",
-                            "Underlying exception : " + generationFailed),
-                    generationFailed);
+                            "Underlying exception : " + failure),
+                failure);
         }
-        if (Modifier.isPrivate(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isPrivate(creationFeatures.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + creationFeatures.getTypeToMock() + ".",
                             "Most likely it is a private class that is not visible by Mockito",
                             "",
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             ""),
-                    generationFailed);
+                failure);
         }
         throw new MockitoException(
                 join(
-                        "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                        "Mockito cannot mock this class: " + creationFeatures.getTypeToMock() + ".",
                         "",
                         "If you're not sure why you're getting this error, please open an issue on GitHub.",
                         "",
@@ -469,435 +616,283 @@ class InlineDelegateByteBuddyMockMaker
                         "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                         "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                         "",
-                        "Underlying exception : " + generationFailed),
-                generationFailed);
+                        "Underlying exception : " + failure),
+            failure);
     }
 
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
+    public <T> Optional<T> createSpyInstance(
+        MockCreationSettings<T> creationConfig, MockHandler invocationHandler, T instance) {
+        if (instance == null) {
+            throw new MockitoConfigurationException("Spy instance must not be null");
         }
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
+        currentSpy.set(instance);
+        try {
+            return Optional.ofNullable(createMockInstance(creationConfig, invocationHandler, true));
+        } finally {
+            currentSpy.remove();
         }
     }
 
     @Override
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
+    public <T> Class<? extends T> createMockType(MockCreationSettings<T> creationConfig) {
+        try {
+            return classGenerator.mockClass(
+                    MockFeatures.withMockFeatures(
+                            creationConfig.getTypeToMock(),
+                            creationConfig.getExtraInterfaces(),
+                            creationConfig.getSerializableMode(),
+                            creationConfig.isStripAnnotations(),
+                            creationConfig.getDefaultAnswer()));
+        } catch (Exception generationError) {
+            throw formatFailureMessage(creationConfig, generationError);
         }
     }
 
-    @Override
-    public void clearAllMocks() {
-        mockedStatics.getBackingMap().clear();
-        mocks.clear();
+    public <T> T createMockInstance(MockCreationSettings<T> creationConfig, MockHandler invocationHandler) {
+        return createMockInstance(creationConfig, invocationHandler, false);
     }
 
-    @Override
-    public TypeMockability isTypeMockable(final Class<?> type) {
-        return new TypeMockability() {
-            @Override
-            public boolean mockable() {
-                return INSTRUMENTATION.isModifiableClass(type) && !EXCLUDES.contains(type);
-            }
+    private <T> T createMockInstance(
+            MockCreationSettings<T> creationConfig,
+            MockHandler invocationHandler,
+            boolean nullWhenNotInline) {
+        Class<? extends T> targetClass = createMockType(creationConfig);
 
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
+        try {
+            T mockInstance;
+            if (creationConfig.isUsingConstructor()) {
+                mockInstance =
+                        new ConstructorInstantiator(
+                                        creationConfig.getOuterClassInstance() != null,
+                                        creationConfig.getConstructorArgs())
+                                .newInstance(targetClass);
+            } else {
+                try {
+                    // We attempt to use the "native" mock maker first that avoids
+                    // Objenesis and Unsafe
+                    mockInstance = newInstance(targetClass);
+                } catch (InstantiationException suppressed) {
+                    if (nullWhenNotInline) {
+                        return null;
+                    }
+                    Instantiator objectInstantiator =
+                            Plugins.getInstantiatorProvider().getInstantiator(creationConfig);
+                    mockInstance = objectInstantiator.newInstance(targetClass);
                 }
-                return "VM does not support modification of given type";
             }
-        };
+            MockMethodInterceptor methodInterceptor =
+                    new MockMethodInterceptor(invocationHandler, creationConfig);
+            proxyMap.put(mockInstance, methodInterceptor);
+            if (mockInstance instanceof MockAccess) {
+                ((MockAccess) mockInstance).setMockitoInterceptor(methodInterceptor);
+            }
+            proxyMap.expungeStaleEntries();
+            return mockInstance;
+        } catch (InstantiationException ex) {
+            throw new MockitoException(
+                    "Unable to create mock instance of type '" + targetClass.getSimpleName() + "'", ex);
+        }
     }
 
-    @Override
-    public <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
-        if (type == ConcurrentHashMap.class) {
+    public <T> StaticMockControl<T> createInlineStaticMock(
+        Class<T> targetClass, MockCreationSettings<T> creationConfig, MockHandler invocationHandler) {
+        if (targetClass == ConcurrentHashMap.class) {
             throw new MockitoException(
                     "It is not possible to mock static methods of ConcurrentHashMap "
                             + "to avoid infinitive loops within Mockito's implementation of static mock handling");
-        } else if (type == Thread.class
-                || type == System.class
-                || type == Arrays.class
-                || ClassLoader.class.isAssignableFrom(type)) {
+        } else if (targetClass == Thread.class
+                || targetClass == System.class
+                || targetClass == Arrays.class
+                || ClassLoader.class.isAssignableFrom(targetClass)) {
             throw new MockitoException(
                     "It is not possible to mock static methods of "
-                            + type.getName()
+                            + targetClass.getName()
                             + " to avoid interfering with class loading what leads to infinite loops");
         }
 
-        bytecodeGenerator.mockClassStatic(type);
+        classGenerator.mockClassStatic(targetClass);
 
-        Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedStatics.set(interceptors);
+        Map<Class<?>, MockMethodInterceptor> classHandlerMap = staticInterceptors.get();
+        if (classHandlerMap == null) {
+            classHandlerMap = new WeakHashMap<>();
+            staticInterceptors.set(classHandlerMap);
         }
-        mockedStatics.getBackingMap().expungeStaleEntries();
+        staticInterceptors.getBackingMap().expungeStaleEntries();
 
-        return new InlineStaticMockControl<>(type, interceptors, settings, handler);
+        return new InlineStaticMockController<>(targetClass, classHandlerMap, creationConfig, invocationHandler);
     }
 
-    @Override
-    public <T> ConstructionMockControl<T> createConstructionMock(
-            Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
-            Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
-            MockedConstruction.MockInitializer<T> mockInitializer) {
-        if (type == Object.class) {
+    public <T> ConstructionMockControl<T> createConstructionMockController(
+            Class<T> targetClass,
+            Function<MockedConstruction.Context, MockCreationSettings<T>> creationProvider,
+            Function<MockedConstruction.Context, MockHandler<T>> invocationFactory,
+            MockedConstruction.MockInitializer<T> initRoutine) {
+        if (targetClass == Object.class) {
             throw new MockitoException(
                     "It is not possible to mock construction of the Object class "
                             + "to avoid inference with default object constructor chains");
-        } else if (type.isPrimitive() || Modifier.isAbstract(type.getModifiers())) {
+        } else if (targetClass.isPrimitive() || Modifier.isAbstract(targetClass.getModifiers())) {
             throw new MockitoException(
                     "It is not possible to construct primitive types or abstract types: "
-                            + type.getName());
+                            + targetClass.getName());
         }
 
-        bytecodeGenerator.mockClassConstruction(type);
+        classGenerator.mockClassConstruction(targetClass);
 
-        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
-                mockedConstruction.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedConstruction.set(interceptors);
+        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> classHandlerMap =
+                constructionInterceptors.get();
+        if (classHandlerMap == null) {
+            classHandlerMap = new WeakHashMap<>();
+            constructionInterceptors.set(classHandlerMap);
         }
-        mockedConstruction.getBackingMap().expungeStaleEntries();
+        constructionInterceptors.getBackingMap().expungeStaleEntries();
 
-        return new InlineConstructionMockControl<>(
-                type, settingsFactory, handlerFactory, mockInitializer, interceptors);
+        return new InlineConstructionMockController<>(
+            targetClass, creationProvider, invocationFactory, initRoutine, classHandlerMap);
     }
 
     @Override
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
+    public void clearMock(Object mockInstance) {
+        if (mockInstance instanceof Class<?>) {
+            for (Map<Class<?>, ?> typeMap : staticInterceptors.getBackingMap().target.values()) {
+                typeMap.remove(mockInstance);
             }
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
-                                mockitoConstruction.set(true);
-                                try {
-                                    return callback.newInstance();
-                                } finally {
-                                    mockitoConstruction.set(false);
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
         } else {
-            return null;
+            proxyMap.remove(mockInstance);
         }
     }
 
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
-
-        @Override
-        public Class<T> getType() {
-            return type;
-        }
-
-        @Override
-        public void enable() {
-            if (interceptors.putIfAbsent(type, new MockMethodInterceptor(handler, settings))
-                    != null) {
-                throw new MockitoException(
-                        join(
-                                "For "
-                                        + type.getName()
-                                        + ", static mocking is already registered in the current thread",
-                                "",
-                                "To create a new mock, the existing static mock registration must be deregistered"));
-            }
-        }
-
-        @Override
-        public void disable() {
-            if (interceptors.remove(type) == null) {
-                throw new MockitoException(
-                        join(
-                                "Could not deregister "
-                                        + type.getName()
-                                        + " as a static mock since it is not currently registered",
-                                "",
-                                "To register a static mock, use Mockito.mockStatic("
-                                        + type.getSimpleName()
-                                        + ".class)"));
-            }
-        }
+    @Override
+    public void clearAllMocks() {
+        staticInterceptors.getBackingMap().clear();
+        proxyMap.clear();
     }
 
-    private class InlineConstructionMockControl<T> implements ConstructionMockControl<T> {
-
-        private final Class<T> type;
-
-        private final Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory;
-        private final Function<MockedConstruction.Context, MockHandler<T>> handlerFactory;
-
-        private final MockedConstruction.MockInitializer<T> mockInitializer;
-
-        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors;
-
-        private final List<Object> all = new ArrayList<>();
-        private int count;
-
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
-        }
-
-        @Override
-        public Class<T> getType() {
-            return type;
-        }
-
-        @Override
-        public void enable() {
-            if (interceptors.putIfAbsent(
-                            type,
-                            (object, context) -> {
-                                ((InlineConstructionMockContext) context).count = ++count;
-                                MockMethodInterceptor interceptor =
-                                        new MockMethodInterceptor(
-                                                handlerFactory.apply(context),
-                                                settingsFactory.apply(context));
-                                mocks.put(object, interceptor);
-                                try {
-                                    @SuppressWarnings("unchecked")
-                                    T cast = (T) object;
-                                    mockInitializer.prepare(cast, context);
-                                } catch (Throwable t) {
-                                    mocks.remove(object); // TODO: filter stack trace?
-                                    throw new MockitoException(
-                                            "Could not initialize mocked construction", t);
-                                }
-                                all.add(object);
-                            })
-                    != null) {
-                throw new MockitoException(
-                        join(
-                                "For "
-                                        + type.getName()
-                                        + ", static mocking is already registered in the current thread",
-                                "",
-                                "To create a new mock, the existing static mock registration must be deregistered"));
-            }
-        }
-
-        @Override
-        public void disable() {
-            if (interceptors.remove(type) == null) {
-                throw new MockitoException(
-                        join(
-                                "Could not deregister "
-                                        + type.getName()
-                                        + " as a static mock since it is not currently registered",
-                                "",
-                                "To register a static mock, use Mockito.mockStatic("
-                                        + type.getSimpleName()
-                                        + ".class)"));
-            }
-            all.clear();
-        }
-
-        @Override
-        @SuppressWarnings("unchecked")
-        public List<T> getMocks() {
-            return (List<T>) all;
-        }
+    public void clearAllCachesAndMocks() {
+        clearAllMocks();
+        classGenerator.clearAllCaches();
     }
 
-    private static class InlineConstructionMockContext implements MockedConstruction.Context {
-
-        private static final Map<String, Class<?>> PRIMITIVES = new HashMap<>();
-
-        static {
-            PRIMITIVES.put(boolean.class.getName(), boolean.class);
-            PRIMITIVES.put(byte.class.getName(), byte.class);
-            PRIMITIVES.put(short.class.getName(), short.class);
-            PRIMITIVES.put(char.class.getName(), char.class);
-            PRIMITIVES.put(int.class.getName(), int.class);
-            PRIMITIVES.put(long.class.getName(), long.class);
-            PRIMITIVES.put(float.class.getName(), float.class);
-            PRIMITIVES.put(double.class.getName(), double.class);
-        }
-
-        private int count;
-
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
-
-        @Override
-        public int getCount() {
-            if (count == 0) {
-                throw new MockitoConfigurationException(
-                        "mocked construction context is not initialized");
+    InlineByteBuddyMockFactory() {
+        if (STARTUP_EXCEPTION != null) {
+            String message;
+            if (PlatformUtils.isAndroidPlatform() || PlatformUtils.isProbablyTermuxEnvironment()) {
+                message =
+                        "It appears as if you are trying to run this mock maker on Android which does not support the instrumentation API.";
+            } else {
+                try {
+                    if (STARTUP_EXCEPTION instanceof NoClassDefFoundError
+                            && STARTUP_EXCEPTION.getMessage() != null
+                            && STARTUP_EXCEPTION
+                                    .getMessage()
+                                    .startsWith("net/bytebuddy/agent/")) {
+                        message =
+                                join(
+                                        "It seems like you are running Mockito with an incomplete or inconsistent class path. Byte Buddy Agent could not be loaded.",
+                                        "",
+                                        "Byte Buddy Agent is available on Maven Central as 'net.bytebuddy:byte-buddy-agent' with the module name 'net.bytebuddy.agent'.",
+                                        "Normally, your IDE or build tool (such as Maven or Gradle) should take care of your class path completion but ");
+                    } else if (Class.forName("javax.tools.ToolProvider")
+                                    .getMethod("getSystemJavaCompiler")
+                                    .invoke(null)
+                            == null) {
+                        message =
+                                "It appears as if you are running on a JRE. Either install a JDK or add JNA to the class path.";
+                    } else {
+                        message =
+                                "It appears as if your JDK does not supply a working agent attachment mechanism.";
+                    }
+                } catch (Throwable suppressed) {
+                    message =
+                            "It appears as if you are running an incomplete JVM installation that might not support all tooling APIs";
+                }
             }
-            return count;
+            throw new MockitoInitializationException(
+                    join(
+                            "Could not initialize inline Byte Buddy mock maker.",
+                            "",
+                        message,
+                            Platform.describe()),
+                STARTUP_EXCEPTION);
         }
 
-        @Override
-        public Constructor<?> constructor() {
-            Class<?>[] parameterTypes = new Class<?>[parameterTypeNames.length];
-            int index = 0;
-            for (String parameterTypeName : parameterTypeNames) {
-                if (PRIMITIVES.containsKey(parameterTypeName)) {
-                    parameterTypes[index++] = PRIMITIVES.get(parameterTypeName);
-                } else {
+        ThreadLocal<Class<?>> constructingClass = new ThreadLocal<>();
+        ThreadLocal<Boolean> suspendedFlag = ThreadLocal.withInitial(() -> false);
+        Predicate<Class<?>> subclassConstructorTest = StackWalkerChecker.orFallback();
+        Predicate<Class<?>> mockCreationPredicate =
+            targetClass -> {
+                    if (suspendedFlag.get()) {
+                        return false;
+                    } else if (constructionFlag.get() || constructingClass.get() != null) {
+                        return true;
+                    }
+                    Map<Class<?>, ?> classHandlerMap = constructionInterceptors.get();
+                    if (classHandlerMap != null && classHandlerMap.containsKey(targetClass)) {
+                        // We only initiate a construction mock, if the call originates from an
+                        // un-mocked (as suppression is not enabled) subclass constructor.
+                        if (subclassConstructorTest.test(targetClass)) {
+                            return false;
+                        }
+                        constructingClass.set(targetClass);
+                        return true;
+                    } else {
+                        return false;
+                    }
+                };
+        ConstructionCallback constructionCallback =
+                (targetClass, instance, args, paramTypeNames) -> {
+                    if (constructionFlag.get()) {
+                        Object spyInstance = currentSpy.get();
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
+                                                + instance.getClass().getName(),
+                                        instance instanceof Throwable ? (Throwable) instance : null);
+                            } finally {
+                                suspendedFlag.set(false);
+                            }
+                        }
+                    } else if (constructingClass.get() != targetClass) {
+                        return null;
+                    }
+                    constructingClass.remove();
+                    suspendedFlag.set(true);
                     try {
-                        parameterTypes[index++] =
-                                Class.forName(parameterTypeName, false, type.getClassLoader());
-                    } catch (ClassNotFoundException e) {
-                        throw new MockitoException(
-                                "Could not find parameter of type " + parameterTypeName, e);
+                        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> classHandlerMap =
+                                constructionInterceptors.get();
+                        if (classHandlerMap != null) {
+                            BiConsumer<Object, MockedConstruction.Context> constructionHandler =
+                                    classHandlerMap.get(targetClass);
+                            if (constructionHandler != null) {
+                                constructionHandler.accept(
+                                    instance,
+                                        new InlineConstructorMockContext(
+                                            args, instance.getClass(), paramTypeNames));
+                            }
+                        }
+                    } finally {
+                        suspendedFlag.set(false);
                     }
-                }
-            }
-            try {
-                return type.getDeclaredConstructor(parameterTypes);
-            } catch (NoSuchMethodException e) {
-                throw new MockitoException(
-                        join(
-                                "Could not resolve constructor of type",
-                                "",
-                                type.getName(),
-                                "",
-                                "with arguments of types",
-                                Arrays.toString(parameterTypes)),
-                        e);
-            }
-        }
+                    return null;
+                };
 
-        @Override
-        public List<?> arguments() {
-            return Collections.unmodifiableList(Arrays.asList(arguments));
-        }
+        classGenerator =
+                new TypeCachingBytecodeGenerator(
+                        new InlineBytecodeGenerator(
+                            JAVA_AGENT,
+                            proxyMap,
+                            staticInterceptors,
+                            mockCreationPredicate,
+                            constructionCallback),
+                        true);
     }
 }
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..41f3c7269 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -16,18 +16,18 @@ import java.util.function.Function;
 
 public class InlineByteBuddyMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
-    private final InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
+    private final InlineByteBuddyMockFactory inlineDelegateByteBuddyMockMaker;
 
     public InlineByteBuddyMockMaker() {
         try {
-            inlineDelegateByteBuddyMockMaker = new InlineDelegateByteBuddyMockMaker();
+            inlineDelegateByteBuddyMockMaker = new InlineByteBuddyMockFactory();
         } catch (NoClassDefFoundError e) {
             Reporter.missingByteBuddyDependency(e);
             throw e;
         }
     }
 
-    InlineByteBuddyMockMaker(InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
+    InlineByteBuddyMockMaker(InlineByteBuddyMockFactory inlineDelegateByteBuddyMockMaker) {
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
+        return inlineDelegateByteBuddyMockMaker.createInlineStaticMock(type, settings, handler);
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
+        inlineDelegateByteBuddyMockMaker.clearAllCachesAndMocks();
     }
 }
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
index 9069e50b8..2417e3782 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
@@ -14,7 +14,7 @@ import static org.mockito.Mockito.verify;
 
 public class InlineByteBuddyMockMakerTest extends TestBase {
 
-    @Mock private InlineDelegateByteBuddyMockMaker delegate;
+    @Mock private InlineByteBuddyMockFactory delegate;
 
     @Test
     public void should_delegate_call() {
@@ -34,15 +34,15 @@ public class InlineByteBuddyMockMakerTest extends TestBase {
         mockMaker.clearAllMocks();
         mockMaker.clearAllCaches();
 
-        verify(delegate).createMock(creationSettings, handler);
-        verify(delegate).createStaticMock(Object.class, creationSettings, handler);
-        verify(delegate).createConstructionMock(Object.class, null, null, null);
+        verify(delegate).createMockInstance(creationSettings, handler);
+        verify(delegate).createInlineStaticMock(Object.class, creationSettings, handler);
+        verify(delegate).createConstructionMockController(Object.class, null, null, null);
         verify(delegate).createMockType(creationSettings);
         verify(delegate).getHandler(this);
         verify(delegate).isTypeMockable(Object.class);
-        verify(delegate).resetMock(this, handler, creationSettings);
+        verify(delegate).resetMockInterceptor(this, handler, creationSettings);
         verify(delegate).clearMock(this);
         verify(delegate).clearAllMocks();
-        verify(delegate).clearAllCaches();
+        verify(delegate).clearAllCachesAndMocks();
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

