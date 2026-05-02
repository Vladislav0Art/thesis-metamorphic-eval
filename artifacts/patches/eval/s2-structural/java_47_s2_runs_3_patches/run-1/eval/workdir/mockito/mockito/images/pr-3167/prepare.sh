#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout b6554b29ed6c204a0dd4b8a670877fe0ba2e808b

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
index 4cb0b40c0..1a3b274a4 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
@@ -222,272 +222,222 @@ class InlineDelegateByteBuddyMockMaker
 
     private final ThreadLocal<Object> currentSpied = new ThreadLocal<>();
 
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
+    private static class InlineStaticMockControl<T> implements StaticMockControl<T> {
+
+        private final Class<T> type;
+
+        private final Map<Class<?>, MockMethodInterceptor> interceptors;
+
+        private final MockCreationSettings<T> settings;
+
+        private final MockHandler handler;
+
+        @Override
+        public Class<T> getType() {
+            return type;
+        }
+
+        @Override
+        public void enable() {
+            if (interceptors.putIfAbsent(type, new MockMethodInterceptor(handler, settings))
+                    != null) {
+                throw new MockitoException(
+                        join(
+                                "For "
+                                        + type.getName()
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
+        @Override
+        public void disable() {
+            if (interceptors.remove(type) == null) {
+                throw new MockitoException(
+                        join(
+                                "Could not deregister "
+                                        + type.getName()
+                                        + " as a static mock since it is not currently registered",
+                                "",
+                                "To register a static mock, use Mockito.mockStatic("
+                                        + type.getSimpleName()
+                                        + ".class)"));
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
+        private InlineStaticMockControl(
+                Class<T> type,
+                Map<Class<?>, MockMethodInterceptor> interceptors,
+                MockCreationSettings<T> settings,
+                MockHandler handler) {
+            this.type = type;
+            this.interceptors = interceptors;
+            this.settings = settings;
+            this.handler = handler;
+        }
     }
 
-    @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return doCreateMock(settings, handler, false);
-    }
+    private class InlineConstructionMockControl<T> implements ConstructionMockControl<T> {
 
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
+        private final Class<T> type;
+
+        private final Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory;
+        private final Function<MockedConstruction.Context, MockHandler<T>> handlerFactory;
+
+        private final MockedConstruction.MockInitializer<T> mockInitializer;
+
+        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors;
+
+        private final List<Object> all = new ArrayList<>();
+        private int count;
+
+        @Override
+        public Class<T> getType() {
+            return type;
         }
-    }
 
-    private <T> T doCreateMock(
-            MockCreationSettings<T> settings,
-            MockHandler handler,
-            boolean nullOnNonInlineConstruction) {
-        Class<? extends T> type = createMockType(settings);
+        @Override
+        @SuppressWarnings("unchecked")
+        public List<T> getMocks() {
+            return (List<T>) all;
+        }
 
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
+        @Override
+        public void enable() {
+            if (interceptors.putIfAbsent(
+                            type,
+                            (object, context) -> {
+                                ((InlineConstructionMockContext) context).count = ++count;
+                                MockMethodInterceptor interceptor =
+                                        new MockMethodInterceptor(
+                                                handlerFactory.apply(context),
+                                                settingsFactory.apply(context));
+                                mocks.put(object, interceptor);
+                                try {
+                                    @SuppressWarnings("unchecked")
+                                    T cast = (T) object;
+                                    mockInitializer.prepare(cast, context);
+                                } catch (Throwable t) {
+                                    mocks.remove(object); // TODO: filter stack trace?
+                                    throw new MockitoException(
+                                            "Could not initialize mocked construction", t);
+                                }
+                                all.add(object);
+                            })
+                    != null) {
+                throw new MockitoException(
+                        join(
+                                "For "
+                                        + type.getName()
+                                        + ", static mocking is already registered in the current thread",
+                                "",
+                                "To create a new mock, the existing static mock registration must be deregistered"));
             }
-            mocks.expungeStaleEntries();
-            return instance;
-        } catch (InstantiationException e) {
-            throw new MockitoException(
-                    "Unable to create mock instance of type '" + type.getSimpleName() + "'", e);
         }
-    }
 
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
+        @Override
+        public void disable() {
+            if (interceptors.remove(type) == null) {
+                throw new MockitoException(
+                        join(
+                                "Could not deregister "
+                                        + type.getName()
+                                        + " as a static mock since it is not currently registered",
+                                "",
+                                "To register a static mock, use Mockito.mockStatic("
+                                        + type.getSimpleName()
+                                        + ".class)"));
+            }
+            all.clear();
+        }
+
+        private InlineConstructionMockControl(
+                Class<T> type,
+                Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
+                Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
+                MockedConstruction.MockInitializer<T> mockInitializer,
+                Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors) {
+            this.type = type;
+            this.settingsFactory = settingsFactory;
+            this.handlerFactory = handlerFactory;
+            this.mockInitializer = mockInitializer;
+            this.interceptors = interceptors;
         }
     }
 
-    private <T> RuntimeException prettifyFailure(
-            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
-        if (mockFeatures.getTypeToMock().isArray()) {
-            throw new MockitoException(
-                    join("Arrays cannot be mocked: " + mockFeatures.getTypeToMock() + ".", ""),
-                    generationFailed);
+    private static class InlineConstructionMockContext implements MockedConstruction.Context {
+
+        private static final Map<String, Class<?>> PRIMITIVES = new HashMap<>();
+
+        static {
+            PRIMITIVES.put(boolean.class.getName(), boolean.class);
+            PRIMITIVES.put(byte.class.getName(), byte.class);
+            PRIMITIVES.put(short.class.getName(), short.class);
+            PRIMITIVES.put(char.class.getName(), char.class);
+            PRIMITIVES.put(int.class.getName(), int.class);
+            PRIMITIVES.put(long.class.getName(), long.class);
+            PRIMITIVES.put(float.class.getName(), float.class);
+            PRIMITIVES.put(double.class.getName(), double.class);
         }
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
+
+        private int count;
+
+        private final Object[] arguments;
+        private final Class<?> type;
+        private final String[] parameterTypeNames;
+
+        @Override
+        public int getCount() {
+            if (count == 0) {
+                throw new MockitoConfigurationException(
+                        "mocked construction context is not initialized");
+            }
+            return count;
         }
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
+
+        @Override
+        public Constructor<?> constructor() {
+            Class<?>[] parameterTypes = new Class<?>[parameterTypeNames.length];
+            int index = 0;
+            for (String parameterTypeName : parameterTypeNames) {
+                if (PRIMITIVES.containsKey(parameterTypeName)) {
+                    parameterTypes[index++] = PRIMITIVES.get(parameterTypeName);
+                } else {
+                    try {
+                        parameterTypes[index++] =
+                                Class.forName(parameterTypeName, false, type.getClassLoader());
+                    } catch (ClassNotFoundException e) {
+                        throw new MockitoException(
+                                "Could not find parameter of type " + parameterTypeName, e);
+                    }
+                }
+            }
+            try {
+                return type.getDeclaredConstructor(parameterTypes);
+            } catch (NoSuchMethodException e) {
+                throw new MockitoException(
+                        join(
+                                "Could not resolve constructor of type",
+                                "",
+                                type.getName(),
+                                "",
+                                "with arguments of types",
+                                Arrays.toString(parameterTypes)),
+                        e);
+            }
         }
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
 
-    @Override
-    public MockHandler getHandler(Object mock) {
-        MockMethodInterceptor interceptor;
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            interceptor = interceptors != null ? interceptors.get(mock) : null;
-        } else {
-            interceptor = mocks.get(mock);
+        @Override
+        public List<?> arguments() {
+            return Collections.unmodifiableList(Arrays.asList(arguments));
         }
-        if (interceptor == null) {
-            return null;
-        } else {
-            return interceptor.handler;
+
+        private InlineConstructionMockContext(
+                Object[] arguments, Class<?> type, String[] parameterTypeNames) {
+            this.arguments = arguments;
+            this.type = type;
+            this.parameterTypeNames = parameterTypeNames;
         }
     }
 
@@ -517,110 +467,56 @@ class InlineDelegateByteBuddyMockMaker
         }
     }
 
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
+    private <T> RuntimeException prettifyFailure(
+            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
+        if (mockFeatures.getTypeToMock().isArray()) {
             throw new MockitoException(
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
+                    join("Arrays cannot be mocked: " + mockFeatures.getTypeToMock() + ".", ""),
+                    generationFailed);
         }
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
+        if (Modifier.isFinal(mockFeatures.getTypeToMock().getModifiers())) {
             throw new MockitoException(
-                    "It is not possible to construct primitive types or abstract types: "
-                            + type.getName());
+                    join(
+                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Can not mock final classes with the following settings :",
+                            " - explicit serialization (e.g. withSettings().serializable())",
+                            " - extra interfaces (e.g. withSettings().extraInterfaces(...))",
+                            "",
+                            "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
+                            "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
+                            "",
+                            "Underlying exception : " + generationFailed),
+                    generationFailed);
         }
-
-        bytecodeGenerator.mockClassConstruction(type);
-
-        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
-                mockedConstruction.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedConstruction.set(interceptors);
+        if (Modifier.isPrivate(mockFeatures.getTypeToMock().getModifiers())) {
+            throw new MockitoException(
+                    join(
+                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Most likely it is a private class that is not visible by Mockito",
+                            "",
+                            "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
+                            "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
+                            ""),
+                    generationFailed);
         }
-        mockedConstruction.getBackingMap().expungeStaleEntries();
-
-        return new InlineConstructionMockControl<>(
-                type, settingsFactory, handlerFactory, mockInitializer, interceptors);
+        throw new MockitoException(
+                join(
+                        "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
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
+                        "Underlying exception : " + generationFailed),
+                generationFailed);
     }
 
     @Override
@@ -684,222 +580,327 @@ class InlineDelegateByteBuddyMockMaker
         }
     }
 
-    private static class InlineStaticMockControl<T> implements StaticMockControl<T> {
-
-        private final Class<T> type;
-
-        private final Map<Class<?>, MockMethodInterceptor> interceptors;
+    @Override
+    public TypeMockability isTypeMockable(final Class<?> type) {
+        return new TypeMockability() {
 
-        private final MockCreationSettings<T> settings;
+            @Override
+            public String nonMockableReason() {
+                if (mockable()) {
+                    return "";
+                }
+                if (type.isPrimitive()) {
+                    return "primitive type";
+                }
+                if (EXCLUDES.contains(type)) {
+                    return "Cannot mock wrapper types, String.class or Class.class";
+                }
+                return "VM does not support modification of given type";
+            }
 
-        private final MockHandler handler;
+            @Override
+            public boolean mockable() {
+                return INSTRUMENTATION.isModifiableClass(type) && !EXCLUDES.contains(type);
+            }
+        };
+    }
 
-        private InlineStaticMockControl(
-                Class<T> type,
-                Map<Class<?>, MockMethodInterceptor> interceptors,
-                MockCreationSettings<T> settings,
-                MockHandler handler) {
-            this.type = type;
-            this.interceptors = interceptors;
-            this.settings = settings;
-            this.handler = handler;
+    @Override
+    public MockHandler getHandler(Object mock) {
+        MockMethodInterceptor interceptor;
+        if (mock instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
+            interceptor = interceptors != null ? interceptors.get(mock) : null;
+        } else {
+            interceptor = mocks.get(mock);
         }
-
-        @Override
-        public Class<T> getType() {
-            return type;
+        if (interceptor == null) {
+            return null;
+        } else {
+            return interceptor.handler;
         }
+    }
 
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
+    private <T> T doCreateMock(
+            MockCreationSettings<T> settings,
+            MockHandler handler,
+            boolean nullOnNonInlineConstruction) {
+        Class<? extends T> type = createMockType(settings);
 
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
+        try {
+            T instance;
+            if (settings.isUsingConstructor()) {
+                instance =
+                        new ConstructorInstantiator(
+                                        settings.getOuterClassInstance() != null,
+                                        settings.getConstructorArgs())
+                                .newInstance(type);
+            } else {
+                try {
+                    // We attempt to use the "native" mock maker first that avoids
+                    // Objenesis and Unsafe
+                    instance = newInstance(type);
+                } catch (InstantiationException ignored) {
+                    if (nullOnNonInlineConstruction) {
+                        return null;
+                    }
+                    Instantiator instantiator =
+                            Plugins.getInstantiatorProvider().getInstantiator(settings);
+                    instance = instantiator.newInstance(type);
+                }
+            }
+            MockMethodInterceptor mockMethodInterceptor =
+                    new MockMethodInterceptor(handler, settings);
+            mocks.put(instance, mockMethodInterceptor);
+            if (instance instanceof MockAccess) {
+                ((MockAccess) instance).setMockitoInterceptor(mockMethodInterceptor);
             }
+            mocks.expungeStaleEntries();
+            return instance;
+        } catch (InstantiationException e) {
+            throw new MockitoException(
+                    "Unable to create mock instance of type '" + type.getSimpleName() + "'", e);
         }
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
+    @Override
+    public <T> StaticMockControl<T> createStaticMock(
+            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
+        if (type == ConcurrentHashMap.class) {
+            throw new MockitoException(
+                    "It is not possible to mock static methods of ConcurrentHashMap "
+                            + "to avoid infinitive loops within Mockito's implementation of static mock handling");
+        } else if (type == Thread.class
+                || type == System.class
+                || type == Arrays.class
+                || ClassLoader.class.isAssignableFrom(type)) {
+            throw new MockitoException(
+                    "It is not possible to mock static methods of "
+                            + type.getName()
+                            + " to avoid interfering with class loading what leads to infinite loops");
         }
 
-        @Override
-        public Class<T> getType() {
-            return type;
-        }
+        bytecodeGenerator.mockClassStatic(type);
 
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
+        Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
+        if (interceptors == null) {
+            interceptors = new WeakHashMap<>();
+            mockedStatics.set(interceptors);
         }
+        mockedStatics.getBackingMap().expungeStaleEntries();
 
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
+        return new InlineStaticMockControl<>(type, interceptors, settings, handler);
+    }
 
-        @Override
-        @SuppressWarnings("unchecked")
-        public List<T> getMocks() {
-            return (List<T>) all;
+    @Override
+    public <T> Optional<T> createSpy(
+            MockCreationSettings<T> settings, MockHandler handler, T object) {
+        if (object == null) {
+            throw new MockitoConfigurationException("Spy instance must not be null");
+        }
+        currentSpied.set(object);
+        try {
+            return Optional.ofNullable(doCreateMock(settings, handler, true));
+        } finally {
+            currentSpied.remove();
         }
     }
 
-    private static class InlineConstructionMockContext implements MockedConstruction.Context {
+    @Override
+    public <T> Class<? extends T> createMockType(MockCreationSettings<T> settings) {
+        try {
+            return bytecodeGenerator.mockClass(
+                    MockFeatures.withMockFeatures(
+                            settings.getTypeToMock(),
+                            settings.getExtraInterfaces(),
+                            settings.getSerializableMode(),
+                            settings.isStripAnnotations(),
+                            settings.getDefaultAnswer()));
+        } catch (Exception bytecodeGenerationFailed) {
+            throw prettifyFailure(settings, bytecodeGenerationFailed);
+        }
+    }
 
-        private static final Map<String, Class<?>> PRIMITIVES = new HashMap<>();
+    @Override
+    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+        return doCreateMock(settings, handler, false);
+    }
 
-        static {
-            PRIMITIVES.put(boolean.class.getName(), boolean.class);
-            PRIMITIVES.put(byte.class.getName(), byte.class);
-            PRIMITIVES.put(short.class.getName(), short.class);
-            PRIMITIVES.put(char.class.getName(), char.class);
-            PRIMITIVES.put(int.class.getName(), int.class);
-            PRIMITIVES.put(long.class.getName(), long.class);
-            PRIMITIVES.put(float.class.getName(), float.class);
-            PRIMITIVES.put(double.class.getName(), double.class);
+    @Override
+    public <T> ConstructionMockControl<T> createConstructionMock(
+            Class<T> type,
+            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
+            Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
+            MockedConstruction.MockInitializer<T> mockInitializer) {
+        if (type == Object.class) {
+            throw new MockitoException(
+                    "It is not possible to mock construction of the Object class "
+                            + "to avoid inference with default object constructor chains");
+        } else if (type.isPrimitive() || Modifier.isAbstract(type.getModifiers())) {
+            throw new MockitoException(
+                    "It is not possible to construct primitive types or abstract types: "
+                            + type.getName());
         }
 
-        private int count;
-
-        private final Object[] arguments;
-        private final Class<?> type;
-        private final String[] parameterTypeNames;
+        bytecodeGenerator.mockClassConstruction(type);
 
-        private InlineConstructionMockContext(
-                Object[] arguments, Class<?> type, String[] parameterTypeNames) {
-            this.arguments = arguments;
-            this.type = type;
-            this.parameterTypeNames = parameterTypeNames;
+        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
+                mockedConstruction.get();
+        if (interceptors == null) {
+            interceptors = new WeakHashMap<>();
+            mockedConstruction.set(interceptors);
         }
+        mockedConstruction.getBackingMap().expungeStaleEntries();
 
-        @Override
-        public int getCount() {
-            if (count == 0) {
-                throw new MockitoConfigurationException(
-                        "mocked construction context is not initialized");
+        return new InlineConstructionMockControl<>(
+                type, settingsFactory, handlerFactory, mockInitializer, interceptors);
+    }
+
+    @Override
+    public void clearMock(Object mock) {
+        if (mock instanceof Class<?>) {
+            for (Map<Class<?>, ?> entry : mockedStatics.getBackingMap().target.values()) {
+                entry.remove(mock);
             }
-            return count;
+        } else {
+            mocks.remove(mock);
         }
+    }
 
-        @Override
-        public Constructor<?> constructor() {
-            Class<?>[] parameterTypes = new Class<?>[parameterTypeNames.length];
-            int index = 0;
-            for (String parameterTypeName : parameterTypeNames) {
-                if (PRIMITIVES.containsKey(parameterTypeName)) {
-                    parameterTypes[index++] = PRIMITIVES.get(parameterTypeName);
-                } else {
-                    try {
-                        parameterTypes[index++] =
-                                Class.forName(parameterTypeName, false, type.getClassLoader());
-                    } catch (ClassNotFoundException e) {
-                        throw new MockitoException(
-                                "Could not find parameter of type " + parameterTypeName, e);
+    @Override
+    public void clearAllMocks() {
+        mockedStatics.getBackingMap().clear();
+        mocks.clear();
+    }
+
+    @Override
+    public void clearAllCaches() {
+        clearAllMocks();
+        bytecodeGenerator.clearAllCaches();
+    }
+
+    InlineDelegateByteBuddyMockMaker() {
+        if (INITIALIZATION_ERROR != null) {
+            String detail;
+            if (PlatformUtils.isAndroidPlatform() || PlatformUtils.isProbablyTermuxEnvironment()) {
+                detail =
+                        "It appears as if you are trying to run this mock maker on Android which does not support the instrumentation API.";
+            } else {
+                try {
+                    if (INITIALIZATION_ERROR instanceof NoClassDefFoundError
+                            && INITIALIZATION_ERROR.getMessage() != null
+                            && INITIALIZATION_ERROR
+                                    .getMessage()
+                                    .startsWith("net/bytebuddy/agent/")) {
+                        detail =
+                                join(
+                                        "It seems like you are running Mockito with an incomplete or inconsistent class path. Byte Buddy Agent could not be loaded.",
+                                        "",
+                                        "Byte Buddy Agent is available on Maven Central as 'net.bytebuddy:byte-buddy-agent' with the module name 'net.bytebuddy.agent'.",
+                                        "Normally, your IDE or build tool (such as Maven or Gradle) should take care of your class path completion but ");
+                    } else if (Class.forName("javax.tools.ToolProvider")
+                                    .getMethod("getSystemJavaCompiler")
+                                    .invoke(null)
+                            == null) {
+                        detail =
+                                "It appears as if you are running on a JRE. Either install a JDK or add JNA to the class path.";
+                    } else {
+                        detail =
+                                "It appears as if your JDK does not supply a working agent attachment mechanism.";
                     }
+                } catch (Throwable ignored) {
+                    detail =
+                            "It appears as if you are running an incomplete JVM installation that might not support all tooling APIs";
                 }
             }
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
+            throw new MockitoInitializationException(
+                    join(
+                            "Could not initialize inline Byte Buddy mock maker.",
+                            "",
+                            detail,
+                            Platform.describe()),
+                    INITIALIZATION_ERROR);
         }
 
-        @Override
-        public List<?> arguments() {
-            return Collections.unmodifiableList(Arrays.asList(arguments));
-        }
+        ThreadLocal<Class<?>> currentConstruction = new ThreadLocal<>();
+        ThreadLocal<Boolean> isSuspended = ThreadLocal.withInitial(() -> false);
+        Predicate<Class<?>> isCallFromSubclassConstructor = StackWalkerChecker.orFallback();
+        Predicate<Class<?>> isMockConstruction =
+                type -> {
+                    if (isSuspended.get()) {
+                        return false;
+                    } else if ((currentMocking.get() != null
+                                    && type.isAssignableFrom(currentMocking.get()))
+                            || currentConstruction.get() != null) {
+                        return true;
+                    }
+                    Map<Class<?>, ?> interceptors = mockedConstruction.get();
+                    if (interceptors != null && interceptors.containsKey(type)) {
+                        // We only initiate a construction mock, if the call originates from an
+                        // un-mocked (as suppression is not enabled) subclass constructor.
+                        if (isCallFromSubclassConstructor.test(type)) {
+                            return false;
+                        }
+                        currentConstruction.set(type);
+                        return true;
+                    } else {
+                        return false;
+                    }
+                };
+        ConstructionCallback onConstruction =
+                (type, object, arguments, parameterTypeNames) -> {
+                    if (currentMocking.get() != null) {
+                        Object spy = currentSpied.get();
+                        if (spy == null) {
+                            return null;
+                        } else if (type.isInstance(spy)) {
+                            return spy;
+                        } else {
+                            isSuspended.set(true);
+                            try {
+                                // Unexpected construction of non-spied object
+                                throw new MockitoException(
+                                        "Unexpected spy for "
+                                                + type.getName()
+                                                + " on instance of "
+                                                + object.getClass().getName(),
+                                        object instanceof Throwable ? (Throwable) object : null);
+                            } finally {
+                                isSuspended.set(false);
+                            }
+                        }
+                    } else if (currentConstruction.get() != type) {
+                        return null;
+                    }
+                    currentConstruction.remove();
+                    isSuspended.set(true);
+                    try {
+                        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
+                                mockedConstruction.get();
+                        if (interceptors != null) {
+                            BiConsumer<Object, MockedConstruction.Context> interceptor =
+                                    interceptors.get(type);
+                            if (interceptor != null) {
+                                interceptor.accept(
+                                        object,
+                                        new InlineConstructionMockContext(
+                                                arguments, object.getClass(), parameterTypeNames));
+                            }
+                        }
+                    } finally {
+                        isSuspended.set(false);
+                    }
+                    return null;
+                };
+
+        bytecodeGenerator =
+                new TypeCachingBytecodeGenerator(
+                        new InlineBytecodeGenerator(
+                                INSTRUMENTATION,
+                                mocks,
+                                mockedStatics,
+                                isMockConstruction,
+                                onConstruction),
+                        true);
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

