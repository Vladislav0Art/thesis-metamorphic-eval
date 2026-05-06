#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout bfee15dda7acc41ef497d8f8a44c74dacce2933a

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/DelegateByteBuddyMockMaker.java
similarity index 56%
rename from src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
rename to src/main/java/org/mockito/internal/creation/bytebuddy/DelegateByteBuddyMockMaker.java
index 227df4cd1..88787ef6b 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/DelegateByteBuddyMockMaker.java
@@ -100,12 +100,12 @@ import static org.mockito.internal.util.StringUtil.join;
  * support this feature.
  */
 @SuppressSignatureCheck
-class InlineDelegateByteBuddyMockMaker
+class DelegateByteBuddyMockMaker
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
+                            DelegateByteBuddyMockMaker.class
                                     .getClassLoader()
                                     .getResourceAsStream(source + ".raw");
                     if (inputStream == null) {
@@ -156,7 +156,7 @@ class InlineDelegateByteBuddyMockMaker
                                                 + ".raw",
                                         "",
                                         "The class loader responsible for looking up the resource: "
-                                                + InlineDelegateByteBuddyMockMaker.class
+                                                + DelegateByteBuddyMockMaker.class
                                                         .getClassLoader()));
                     }
                     outputStream.putNextEntry(new JarEntry(source + ".class"));
@@ -203,39 +203,39 @@ class InlineDelegateByteBuddyMockMaker
             instrumentation = null;
             initializationError = throwable;
         }
-        INSTRUMENTATION = instrumentation;
-        INITIALIZATION_ERROR = initializationError;
+        JAVA_AGENT = instrumentation;
+        STARTUP_EXCEPTION = initializationError;
     }
 
-    private final BytecodeGenerator bytecodeGenerator;
+    private final BytecodeGenerator codeGenerator;
 
-    private final WeakConcurrentMap<Object, MockMethodInterceptor> mocks =
+    private final WeakConcurrentMap<Object, MockMethodInterceptor> mockRegistry =
             new WeakConcurrentMap<>(false);
 
-    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> mockedStatics =
+    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> staticMockRegistry =
             new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
     private final DetachedThreadLocal<Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>>>
-            mockedConstruction = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
+        constructionMockRegistry = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
-    private final ThreadLocal<Boolean> mockitoConstruction = ThreadLocal.withInitial(() -> false);
+    private final ThreadLocal<Boolean> inConstructionMode = ThreadLocal.withInitial(() -> false);
 
-    private final ThreadLocal<Object> currentSpied = new ThreadLocal<>();
+    private final ThreadLocal<Object> activeSpy = new ThreadLocal<>();
 
-    InlineDelegateByteBuddyMockMaker() {
-        if (INITIALIZATION_ERROR != null) {
-            String detail;
+    DelegateByteBuddyMockMaker() {
+        if (STARTUP_EXCEPTION != null) {
+            String messageDetail;
             if (PlatformUtils.isAndroidPlatform() || PlatformUtils.isProbablyTermuxEnvironment()) {
-                detail =
+                messageDetail =
                         "It appears as if you are trying to run this mock maker on Android which does not support the instrumentation API.";
             } else {
                 try {
-                    if (INITIALIZATION_ERROR instanceof NoClassDefFoundError
-                            && INITIALIZATION_ERROR.getMessage() != null
-                            && INITIALIZATION_ERROR
+                    if (STARTUP_EXCEPTION instanceof NoClassDefFoundError
+                            && STARTUP_EXCEPTION.getMessage() != null
+                            && STARTUP_EXCEPTION
                                     .getMessage()
                                     .startsWith("net/bytebuddy/agent/")) {
-                        detail =
+                        messageDetail =
                                 join(
                                         "It seems like you are running Mockito with an incomplete or inconsistent class path. Byte Buddy Agent could not be loaded.",
                                         "",
@@ -245,14 +245,14 @@ class InlineDelegateByteBuddyMockMaker
                                     .getMethod("getSystemJavaCompiler")
                                     .invoke(null)
                             == null) {
-                        detail =
+                        messageDetail =
                                 "It appears as if you are running on a JRE. Either install a JDK or add JNA to the class path.";
                     } else {
-                        detail =
+                        messageDetail =
                                 "It appears as if your JDK does not supply a working agent attachment mechanism.";
                     }
-                } catch (Throwable ignored) {
-                    detail =
+                } catch (Throwable suppressedError) {
+                    messageDetail =
                             "It appears as if you are running an incomplete JVM installation that might not support all tooling APIs";
                 }
             }
@@ -260,178 +260,176 @@ class InlineDelegateByteBuddyMockMaker
                     join(
                             "Could not initialize inline Byte Buddy mock maker.",
                             "",
-                            detail,
+                        messageDetail,
                             Platform.describe()),
-                    INITIALIZATION_ERROR);
+                STARTUP_EXCEPTION);
         }
 
-        ThreadLocal<Class<?>> currentConstruction = new ThreadLocal<>();
-        ThreadLocal<Boolean> isSuspended = ThreadLocal.withInitial(() -> false);
-        Predicate<Class<?>> isCallFromSubclassConstructor = StackWalkerChecker.orFallback();
-        Predicate<Class<?>> isMockConstruction =
-                type -> {
-                    if (isSuspended.get()) {
+        ThreadLocal<Class<?>> currentConstructingClass = new ThreadLocal<>();
+        ThreadLocal<Boolean> suspendedFlag = ThreadLocal.withInitial(() -> false);
+        Predicate<Class<?>> fromSubclassConstructor = StackWalkerChecker.orFallback();
+        Predicate<Class<?>> mockConstructionCheck =
+            targetClass -> {
+                    if (suspendedFlag.get()) {
                         return false;
-                    } else if (mockitoConstruction.get() || currentConstruction.get() != null) {
+                    } else if (inConstructionMode.get() || currentConstructingClass.get() != null) {
                         return true;
                     }
-                    Map<Class<?>, ?> interceptors = mockedConstruction.get();
-                    if (interceptors != null && interceptors.containsKey(type)) {
+                    Map<Class<?>, ?> interceptorMap = constructionMockRegistry.get();
+                    if (interceptorMap != null && interceptorMap.containsKey(targetClass)) {
                         // We only initiate a construction mock, if the call originates from an
                         // un-mocked (as suppression is not enabled) subclass constructor.
-                        if (isCallFromSubclassConstructor.test(type)) {
+                        if (fromSubclassConstructor.test(targetClass)) {
                             return false;
                         }
-                        currentConstruction.set(type);
+                        currentConstructingClass.set(targetClass);
                         return true;
                     } else {
                         return false;
                     }
                 };
-        ConstructionCallback onConstruction =
-                (type, object, arguments, parameterTypeNames) -> {
-                    if (mockitoConstruction.get()) {
-                        Object spy = currentSpied.get();
-                        if (spy == null) {
+        ConstructionCallback constructionCallback =
+                (targetClass, instanceObj, argsArray, paramTypeNames) -> {
+                    if (inConstructionMode.get()) {
+                        Object spyInstance = activeSpy.get();
+                        if (spyInstance == null) {
                             return null;
-                        } else if (type.isInstance(spy)) {
-                            return spy;
+                        } else if (targetClass.isInstance(spyInstance)) {
+                            return spyInstance;
                         } else {
-                            isSuspended.set(true);
+                            suspendedFlag.set(true);
                             try {
                                 // Unexpected construction of non-spied object
                                 throw new MockitoException(
                                         "Unexpected spy for "
-                                                + type.getName()
+                                                + targetClass.getName()
                                                 + " on instance of "
-                                                + object.getClass().getName(),
-                                        object instanceof Throwable ? (Throwable) object : null);
+                                                + instanceObj.getClass().getName(),
+                                        instanceObj instanceof Throwable ? (Throwable) instanceObj : null);
                             } finally {
-                                isSuspended.set(false);
+                                suspendedFlag.set(false);
                             }
                         }
-                    } else if (currentConstruction.get() != type) {
+                    } else if (currentConstructingClass.get() != targetClass) {
                         return null;
                     }
-                    currentConstruction.remove();
-                    isSuspended.set(true);
+                    currentConstructingClass.remove();
+                    suspendedFlag.set(true);
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
+                        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap =
+                                constructionMockRegistry.get();
+                        if (interceptorMap != null) {
+                            BiConsumer<Object, MockedConstruction.Context> handlerCallback =
+                                    interceptorMap.get(targetClass);
+                            if (handlerCallback != null) {
+                                handlerCallback.accept(
+                                    instanceObj,
+                                        new InlineConstructorMockContext(
+                                            argsArray, instanceObj.getClass(), paramTypeNames));
                             }
                         }
                     } finally {
-                        isSuspended.set(false);
+                        suspendedFlag.set(false);
                     }
                     return null;
                 };
 
-        bytecodeGenerator =
+        codeGenerator =
                 new TypeCachingBytecodeGenerator(
                         new InlineBytecodeGenerator(
-                                INSTRUMENTATION,
-                                mocks,
-                                mockedStatics,
-                                isMockConstruction,
-                                onConstruction),
+                            JAVA_AGENT,
+                            mockRegistry,
+                            staticMockRegistry,
+                            mockConstructionCheck,
+                            constructionCallback),
                         true);
     }
 
-    @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return doCreateMock(settings, handler, false);
+    public <T> T createMockInstance(MockCreationSettings<T> creationSettings, MockHandler mockHandlerInstance) {
+        return createMock(creationSettings, mockHandlerInstance, false);
     }
 
-    @Override
-    public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T object) {
-        if (object == null) {
+    public <T> Optional<T> createSpyInstance(
+        MockCreationSettings<T> creationSettings, MockHandler mockHandlerInstance, T instanceObj) {
+        if (instanceObj == null) {
             throw new MockitoConfigurationException("Spy instance must not be null");
         }
-        currentSpied.set(object);
+        activeSpy.set(instanceObj);
         try {
-            return Optional.ofNullable(doCreateMock(settings, handler, true));
+            return Optional.ofNullable(createMock(creationSettings, mockHandlerInstance, true));
         } finally {
-            currentSpied.remove();
+            activeSpy.remove();
         }
     }
 
-    private <T> T doCreateMock(
-            MockCreationSettings<T> settings,
-            MockHandler handler,
-            boolean nullOnNonInlineConstruction) {
-        Class<? extends T> type = createMockType(settings);
+    private <T> T createMock(
+            MockCreationSettings<T> creationSettings,
+            MockHandler mockHandlerInstance,
+            boolean returnNullOnNonInline) {
+        Class<? extends T> targetClass = createMockType(creationSettings);
 
         try {
-            T instance;
-            if (settings.isUsingConstructor()) {
-                instance =
+            T createdInstance;
+            if (creationSettings.isUsingConstructor()) {
+                createdInstance =
                         new ConstructorInstantiator(
-                                        settings.getOuterClassInstance() != null,
-                                        settings.getConstructorArgs())
-                                .newInstance(type);
+                                        creationSettings.getOuterClassInstance() != null,
+                                        creationSettings.getConstructorArgs())
+                                .newInstance(targetClass);
             } else {
                 try {
                     // We attempt to use the "native" mock maker first that avoids
                     // Objenesis and Unsafe
-                    instance = newInstance(type);
-                } catch (InstantiationException ignored) {
-                    if (nullOnNonInlineConstruction) {
+                    createdInstance = newInstance(targetClass);
+                } catch (InstantiationException suppressedError) {
+                    if (returnNullOnNonInline) {
                         return null;
                     }
-                    Instantiator instantiator =
-                            Plugins.getInstantiatorProvider().getInstantiator(settings);
-                    instance = instantiator.newInstance(type);
+                    Instantiator objectInstantiator =
+                            Plugins.getInstantiatorProvider().getInstantiator(creationSettings);
+                    createdInstance = objectInstantiator.newInstance(targetClass);
                 }
             }
-            MockMethodInterceptor mockMethodInterceptor =
-                    new MockMethodInterceptor(handler, settings);
-            mocks.put(instance, mockMethodInterceptor);
-            if (instance instanceof MockAccess) {
-                ((MockAccess) instance).setMockitoInterceptor(mockMethodInterceptor);
+            MockMethodInterceptor methodInterceptorInstance =
+                    new MockMethodInterceptor(mockHandlerInstance, creationSettings);
+            mockRegistry.put(createdInstance, methodInterceptorInstance);
+            if (createdInstance instanceof MockAccess) {
+                ((MockAccess) createdInstance).setMockitoInterceptor(methodInterceptorInstance);
             }
-            mocks.expungeStaleEntries();
-            return instance;
-        } catch (InstantiationException e) {
+            mockRegistry.expungeStaleEntries();
+            return createdInstance;
+        } catch (InstantiationException ex) {
             throw new MockitoException(
-                    "Unable to create mock instance of type '" + type.getSimpleName() + "'", e);
+                    "Unable to create mock instance of type '" + targetClass.getSimpleName() + "'", ex);
         }
     }
 
     @Override
-    public <T> Class<? extends T> createMockType(MockCreationSettings<T> settings) {
+    public <T> Class<? extends T> createMockType(MockCreationSettings<T> creationSettings) {
         try {
-            return bytecodeGenerator.mockClass(
+            return codeGenerator.mockClass(
                     MockFeatures.withMockFeatures(
-                            settings.getTypeToMock(),
-                            settings.getExtraInterfaces(),
-                            settings.getSerializableMode(),
-                            settings.isStripAnnotations(),
-                            settings.getDefaultAnswer()));
-        } catch (Exception bytecodeGenerationFailed) {
-            throw prettifyFailure(settings, bytecodeGenerationFailed);
+                            creationSettings.getTypeToMock(),
+                            creationSettings.getExtraInterfaces(),
+                            creationSettings.getSerializableMode(),
+                            creationSettings.isStripAnnotations(),
+                            creationSettings.getDefaultAnswer()));
+        } catch (Exception generationFailure) {
+            throw formatFailureMessage(creationSettings, generationFailure);
         }
     }
 
-    private <T> RuntimeException prettifyFailure(
-            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
-        if (mockFeatures.getTypeToMock().isArray()) {
+    private <T> RuntimeException formatFailureMessage(
+        MockCreationSettings<T> mockCreationFeatures, Exception generationFailure) {
+        if (mockCreationFeatures.getTypeToMock().isArray()) {
             throw new MockitoException(
-                    join("Arrays cannot be mocked: " + mockFeatures.getTypeToMock() + ".", ""),
-                    generationFailed);
+                    join("Arrays cannot be mocked: " + mockCreationFeatures.getTypeToMock() + ".", ""),
+                generationFailure);
         }
-        if (Modifier.isFinal(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isFinal(mockCreationFeatures.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + mockCreationFeatures.getTypeToMock() + ".",
                             "Can not mock final classes with the following settings :",
                             " - explicit serialization (e.g. withSettings().serializable())",
                             " - extra interfaces (e.g. withSettings().extraInterfaces(...))",
@@ -439,23 +437,23 @@ class InlineDelegateByteBuddyMockMaker
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             "",
-                            "Underlying exception : " + generationFailed),
-                    generationFailed);
+                            "Underlying exception : " + generationFailure),
+                generationFailure);
         }
-        if (Modifier.isPrivate(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isPrivate(mockCreationFeatures.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + mockCreationFeatures.getTypeToMock() + ".",
                             "Most likely it is a private class that is not visible by Mockito",
                             "",
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             ""),
-                    generationFailed);
+                generationFailure);
         }
         throw new MockitoException(
                 join(
-                        "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                        "Mockito cannot mock this class: " + mockCreationFeatures.getTypeToMock() + ".",
                         "",
                         "If you're not sure why you're getting this error, please open an issue on GitHub.",
                         "",
@@ -469,81 +467,79 @@ class InlineDelegateByteBuddyMockMaker
                         "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                         "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                         "",
-                        "Underlying exception : " + generationFailed),
-                generationFailed);
+                        "Underlying exception : " + generationFailure),
+            generationFailure);
     }
 
     @Override
-    public MockHandler getHandler(Object mock) {
-        MockMethodInterceptor interceptor;
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            interceptor = interceptors != null ? interceptors.get(mock) : null;
+    public MockHandler getHandler(Object mockObject) {
+        MockMethodInterceptor handlerCallback;
+        if (mockObject instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptorMap = staticMockRegistry.get();
+            handlerCallback = interceptorMap != null ? interceptorMap.get(mockObject) : null;
         } else {
-            interceptor = mocks.get(mock);
+            handlerCallback = mockRegistry.get(mockObject);
         }
-        if (interceptor == null) {
+        if (handlerCallback == null) {
             return null;
         } else {
-            return interceptor.handler;
+            return handlerCallback.handler;
         }
     }
 
-    @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
-        MockMethodInterceptor mockMethodInterceptor =
-                new MockMethodInterceptor(newHandler, settings);
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            if (interceptors == null || !interceptors.containsKey(mock)) {
+    public void resetMockInterceptor(Object mockObject, MockHandler replacementHandler, MockCreationSettings creationSettings) {
+        MockMethodInterceptor methodInterceptorInstance =
+                new MockMethodInterceptor(replacementHandler, creationSettings);
+        if (mockObject instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptorMap = staticMockRegistry.get();
+            if (interceptorMap == null || !interceptorMap.containsKey(mockObject)) {
                 throw new MockitoException(
                         "Cannot reset "
-                                + mock
+                                + mockObject
                                 + " which is not currently registered as a static mock");
             }
-            interceptors.put((Class<?>) mock, mockMethodInterceptor);
+            interceptorMap.put((Class<?>) mockObject, methodInterceptorInstance);
         } else {
-            if (!mocks.containsKey(mock)) {
+            if (!mockRegistry.containsKey(mockObject)) {
                 throw new MockitoException(
-                        "Cannot reset " + mock + " which is not currently registered as a mock");
+                        "Cannot reset " + mockObject + " which is not currently registered as a mock");
             }
-            mocks.put(mock, mockMethodInterceptor);
-            if (mock instanceof MockAccess) {
-                ((MockAccess) mock).setMockitoInterceptor(mockMethodInterceptor);
+            mockRegistry.put(mockObject, methodInterceptorInstance);
+            if (mockObject instanceof MockAccess) {
+                ((MockAccess) mockObject).setMockitoInterceptor(methodInterceptorInstance);
             }
-            mocks.expungeStaleEntries();
+            mockRegistry.expungeStaleEntries();
         }
     }
 
-    @Override
-    public void clearAllCaches() {
+    public void clearAllMocksAndCaches() {
         clearAllMocks();
-        bytecodeGenerator.clearAllCaches();
+        codeGenerator.clearAllCaches();
     }
 
     @Override
-    public void clearMock(Object mock) {
-        if (mock instanceof Class<?>) {
-            for (Map<Class<?>, ?> entry : mockedStatics.getBackingMap().target.values()) {
-                entry.remove(mock);
+    public void clearMock(Object mockObject) {
+        if (mockObject instanceof Class<?>) {
+            for (Map<Class<?>, ?> classEntry : staticMockRegistry.getBackingMap().target.values()) {
+                classEntry.remove(mockObject);
             }
         } else {
-            mocks.remove(mock);
+            mockRegistry.remove(mockObject);
         }
     }
 
     @Override
     public void clearAllMocks() {
-        mockedStatics.getBackingMap().clear();
-        mocks.clear();
+        staticMockRegistry.getBackingMap().clear();
+        mockRegistry.clear();
     }
 
     @Override
-    public TypeMockability isTypeMockable(final Class<?> type) {
+    public TypeMockability isTypeMockable(final Class<?> targetClass) {
         return new TypeMockability() {
             @Override
             public boolean mockable() {
-                return INSTRUMENTATION.isModifiableClass(type) && !EXCLUDES.contains(type);
+                return JAVA_AGENT.isModifiableClass(targetClass) && !EXCLUDES.contains(targetClass);
             }
 
             @Override
@@ -551,10 +547,10 @@ class InlineDelegateByteBuddyMockMaker
                 if (mockable()) {
                     return "";
                 }
-                if (type.isPrimitive()) {
+                if (targetClass.isPrimitive()) {
                     return "primitive type";
                 }
-                if (EXCLUDES.contains(type)) {
+                if (EXCLUDES.contains(targetClass)) {
                     return "Cannot mock wrapper types, String.class or Class.class";
                 }
                 return "VM does not support modification of given type";
@@ -562,160 +558,158 @@ class InlineDelegateByteBuddyMockMaker
         };
     }
 
-    @Override
-    public <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
-        if (type == ConcurrentHashMap.class) {
+    public <T> StaticMockControl<T> createStaticClassMock(
+        Class<T> targetClass, MockCreationSettings<T> creationSettings, MockHandler mockHandlerInstance) {
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
+        codeGenerator.mockClassStatic(targetClass);
 
-        Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedStatics.set(interceptors);
+        Map<Class<?>, MockMethodInterceptor> interceptorMap = staticMockRegistry.get();
+        if (interceptorMap == null) {
+            interceptorMap = new WeakHashMap<>();
+            staticMockRegistry.set(interceptorMap);
         }
-        mockedStatics.getBackingMap().expungeStaleEntries();
+        staticMockRegistry.getBackingMap().expungeStaleEntries();
 
-        return new InlineStaticMockControl<>(type, interceptors, settings, handler);
+        return new InlineStaticMockController<>(targetClass, interceptorMap, creationSettings, mockHandlerInstance);
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
+            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsProvider,
+            Function<MockedConstruction.Context, MockHandler<T>> handlerProvider,
+            MockedConstruction.MockInitializer<T> initializer) {
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
+        codeGenerator.mockClassConstruction(targetClass);
 
-        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
-                mockedConstruction.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedConstruction.set(interceptors);
+        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap =
+                constructionMockRegistry.get();
+        if (interceptorMap == null) {
+            interceptorMap = new WeakHashMap<>();
+            constructionMockRegistry.set(interceptorMap);
         }
-        mockedConstruction.getBackingMap().expungeStaleEntries();
+        constructionMockRegistry.getBackingMap().expungeStaleEntries();
 
-        return new InlineConstructionMockControl<>(
-                type, settingsFactory, handlerFactory, mockInitializer, interceptors);
+        return new InlineConstructionMockController<>(
+            targetClass, settingsProvider, handlerProvider, initializer, interceptorMap);
     }
 
     @Override
     @SuppressWarnings("unchecked")
-    public <T> T newInstance(Class<T> cls) throws InstantiationException {
-        Constructor<?>[] constructors = cls.getDeclaredConstructors();
-        if (constructors.length == 0) {
-            throw new InstantiationException(cls.getName() + " does not define a constructor");
-        }
-        Constructor<?> selected = constructors[0];
-        for (Constructor<?> constructor : constructors) {
-            if (Modifier.isPublic(constructor.getModifiers())) {
-                selected = constructor;
+    public <T> T newInstance(Class<T> clazz) throws InstantiationException {
+        Constructor<?>[] availableConstructors = clazz.getDeclaredConstructors();
+        if (availableConstructors.length == 0) {
+            throw new InstantiationException(clazz.getName() + " does not define a constructor");
+        }
+        Constructor<?> chosenConstructor = availableConstructors[0];
+        for (Constructor<?> ctor : availableConstructors) {
+            if (Modifier.isPublic(ctor.getModifiers())) {
+                chosenConstructor = ctor;
                 break;
             }
         }
-        Class<?>[] types = selected.getParameterTypes();
-        Object[] arguments = new Object[types.length];
-        int index = 0;
-        for (Class<?> type : types) {
-            arguments[index++] = makeStandardArgument(type);
+        Class<?>[] paramTypes = chosenConstructor.getParameterTypes();
+        Object[] argsArray = new Object[paramTypes.length];
+        int pos = 0;
+        for (Class<?> targetClass : paramTypes) {
+            argsArray[pos++] = makeDefaultArgument(targetClass);
         }
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor memberAccessorInstance = Plugins.getMemberAccessor();
         try {
             return (T)
-                    accessor.newInstance(
-                            selected,
-                            callback -> {
-                                mockitoConstruction.set(true);
+                    memberAccessorInstance.newInstance(
+                        chosenConstructor,
+                        constructionDispatcherCallback -> {
+                                inConstructionMode.set(true);
                                 try {
-                                    return callback.newInstance();
+                                    return constructionDispatcherCallback.newInstance();
                                 } finally {
-                                    mockitoConstruction.set(false);
+                                    inConstructionMode.set(false);
                                 }
                             },
-                            arguments);
-        } catch (Exception e) {
-            throw new InstantiationException("Could not instantiate " + cls.getName(), e);
+                        argsArray);
+        } catch (Exception ex) {
+            throw new InstantiationException("Could not instantiate " + clazz.getName(), ex);
         }
     }
 
-    private Object makeStandardArgument(Class<?> type) {
-        if (type == boolean.class) {
+    private Object makeDefaultArgument(Class<?> targetClass) {
+        if (targetClass == boolean.class) {
             return false;
-        } else if (type == byte.class) {
+        } else if (targetClass == byte.class) {
             return (byte) 0;
-        } else if (type == short.class) {
+        } else if (targetClass == short.class) {
             return (short) 0;
-        } else if (type == char.class) {
+        } else if (targetClass == char.class) {
             return (char) 0;
-        } else if (type == int.class) {
+        } else if (targetClass == int.class) {
             return 0;
-        } else if (type == long.class) {
+        } else if (targetClass == long.class) {
             return 0L;
-        } else if (type == float.class) {
+        } else if (targetClass == float.class) {
             return 0f;
-        } else if (type == double.class) {
+        } else if (targetClass == double.class) {
             return 0d;
         } else {
             return null;
         }
     }
 
-    private static class InlineStaticMockControl<T> implements StaticMockControl<T> {
+    private static class InlineStaticMockController<T> implements StaticMockControl<T> {
 
-        private final Class<T> type;
+        private final Class<T> targetClass;
 
-        private final Map<Class<?>, MockMethodInterceptor> interceptors;
+        private final Map<Class<?>, MockMethodInterceptor> interceptorMap;
 
-        private final MockCreationSettings<T> settings;
+        private final MockCreationSettings<T> creationSettings;
 
-        private final MockHandler handler;
+        private final MockHandler mockHandlerInstance;
 
-        private InlineStaticMockControl(
-                Class<T> type,
-                Map<Class<?>, MockMethodInterceptor> interceptors,
-                MockCreationSettings<T> settings,
-                MockHandler handler) {
-            this.type = type;
-            this.interceptors = interceptors;
-            this.settings = settings;
-            this.handler = handler;
+        private InlineStaticMockController(
+                Class<T> targetClass,
+                Map<Class<?>, MockMethodInterceptor> interceptorMap,
+                MockCreationSettings<T> creationSettings,
+                MockHandler mockHandlerInstance) {
+            this.targetClass = targetClass;
+            this.interceptorMap = interceptorMap;
+            this.creationSettings = creationSettings;
+            this.mockHandlerInstance = mockHandlerInstance;
         }
 
         @Override
         public Class<T> getType() {
-            return type;
+            return targetClass;
         }
 
         @Override
         public void enable() {
-            if (interceptors.putIfAbsent(type, new MockMethodInterceptor(handler, settings))
+            if (interceptorMap.putIfAbsent(targetClass, new MockMethodInterceptor(mockHandlerInstance, creationSettings))
                     != null) {
                 throw new MockitoException(
                         join(
                                 "For "
-                                        + type.getName()
+                                        + targetClass.getName()
                                         + ", static mocking is already registered in the current thread",
                                 "",
                                 "To create a new mock, the existing static mock registration must be deregistered"));
@@ -724,79 +718,79 @@ class InlineDelegateByteBuddyMockMaker
 
         @Override
         public void disable() {
-            if (interceptors.remove(type) == null) {
+            if (interceptorMap.remove(targetClass) == null) {
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
     }
 
-    private class InlineConstructionMockControl<T> implements ConstructionMockControl<T> {
+    private class InlineConstructionMockController<T> implements ConstructionMockControl<T> {
 
-        private final Class<T> type;
+        private final Class<T> targetClass;
 
-        private final Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory;
-        private final Function<MockedConstruction.Context, MockHandler<T>> handlerFactory;
+        private final Function<MockedConstruction.Context, MockCreationSettings<T>> settingsProvider;
+        private final Function<MockedConstruction.Context, MockHandler<T>> handlerProvider;
 
-        private final MockedConstruction.MockInitializer<T> mockInitializer;
+        private final MockedConstruction.MockInitializer<T> initializer;
 
-        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors;
+        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap;
 
-        private final List<Object> all = new ArrayList<>();
-        private int count;
+        private final List<Object> allInstances = new ArrayList<>();
+        private int instanceCount;
 
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
+        private InlineConstructionMockController(
+                Class<T> targetClass,
+                Function<MockedConstruction.Context, MockCreationSettings<T>> settingsProvider,
+                Function<MockedConstruction.Context, MockHandler<T>> handlerProvider,
+                MockedConstruction.MockInitializer<T> initializer,
+                Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap) {
+            this.targetClass = targetClass;
+            this.settingsProvider = settingsProvider;
+            this.handlerProvider = handlerProvider;
+            this.initializer = initializer;
+            this.interceptorMap = interceptorMap;
         }
 
         @Override
         public Class<T> getType() {
-            return type;
+            return targetClass;
         }
 
         @Override
         public void enable() {
-            if (interceptors.putIfAbsent(
-                            type,
-                            (object, context) -> {
-                                ((InlineConstructionMockContext) context).count = ++count;
-                                MockMethodInterceptor interceptor =
+            if (interceptorMap.putIfAbsent(
+                targetClass,
+                            (instanceObj, invocationContext) -> {
+                                ((InlineConstructorMockContext) invocationContext).instanceCount = ++instanceCount;
+                                MockMethodInterceptor handlerCallback =
                                         new MockMethodInterceptor(
-                                                handlerFactory.apply(context),
-                                                settingsFactory.apply(context));
-                                mocks.put(object, interceptor);
+                                                handlerProvider.apply(invocationContext),
+                                                settingsProvider.apply(invocationContext));
+                                mockRegistry.put(instanceObj, handlerCallback);
                                 try {
                                     @SuppressWarnings("unchecked")
-                                    T cast = (T) object;
-                                    mockInitializer.prepare(cast, context);
-                                } catch (Throwable t) {
-                                    mocks.remove(object); // TODO: filter stack trace?
+                                    T typedInstance = (T) instanceObj;
+                                    initializer.prepare(typedInstance, invocationContext);
+                                } catch (Throwable throwableCause) {
+                                    mockRegistry.remove(instanceObj); // TODO: filter stack trace?
                                     throw new MockitoException(
-                                            "Could not initialize mocked construction", t);
+                                            "Could not initialize mocked construction", throwableCause);
                                 }
-                                all.add(object);
+                                allInstances.add(instanceObj);
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
@@ -805,99 +799,99 @@ class InlineDelegateByteBuddyMockMaker
 
         @Override
         public void disable() {
-            if (interceptors.remove(type) == null) {
+            if (interceptorMap.remove(targetClass) == null) {
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
+            allInstances.clear();
         }
 
         @Override
         @SuppressWarnings("unchecked")
         public List<T> getMocks() {
-            return (List<T>) all;
+            return (List<T>) allInstances;
         }
     }
 
-    private static class InlineConstructionMockContext implements MockedConstruction.Context {
+    private static class InlineConstructorMockContext implements MockedConstruction.Context {
 
-        private static final Map<String, Class<?>> PRIMITIVES = new HashMap<>();
+        private static final Map<String, Class<?>> PRIMITIVE_TYPES = new HashMap<>();
 
         static {
-            PRIMITIVES.put(boolean.class.getName(), boolean.class);
-            PRIMITIVES.put(byte.class.getName(), byte.class);
-            PRIMITIVES.put(short.class.getName(), short.class);
-            PRIMITIVES.put(char.class.getName(), char.class);
-            PRIMITIVES.put(int.class.getName(), int.class);
-            PRIMITIVES.put(long.class.getName(), long.class);
-            PRIMITIVES.put(float.class.getName(), float.class);
-            PRIMITIVES.put(double.class.getName(), double.class);
+            PRIMITIVE_TYPES.put(boolean.class.getName(), boolean.class);
+            PRIMITIVE_TYPES.put(byte.class.getName(), byte.class);
+            PRIMITIVE_TYPES.put(short.class.getName(), short.class);
+            PRIMITIVE_TYPES.put(char.class.getName(), char.class);
+            PRIMITIVE_TYPES.put(int.class.getName(), int.class);
+            PRIMITIVE_TYPES.put(long.class.getName(), long.class);
+            PRIMITIVE_TYPES.put(float.class.getName(), float.class);
+            PRIMITIVE_TYPES.put(double.class.getName(), double.class);
         }
 
-        private int count;
+        private int instanceCount;
 
-        private final Object[] arguments;
-        private final Class<?> type;
-        private final String[] parameterTypeNames;
+        private final Object[] argsArray;
+        private final Class<?> targetClass;
+        private final String[] paramTypeNames;
 
-        private InlineConstructionMockContext(
-                Object[] arguments, Class<?> type, String[] parameterTypeNames) {
-            this.arguments = arguments;
-            this.type = type;
-            this.parameterTypeNames = parameterTypeNames;
+        private InlineConstructorMockContext(
+            Object[] argsArray, Class<?> targetClass, String[] paramTypeNames) {
+            this.argsArray = argsArray;
+            this.targetClass = targetClass;
+            this.paramTypeNames = paramTypeNames;
         }
 
         @Override
         public int getCount() {
-            if (count == 0) {
+            if (instanceCount == 0) {
                 throw new MockitoConfigurationException(
                         "mocked construction context is not initialized");
             }
-            return count;
+            return instanceCount;
         }
 
         @Override
         public Constructor<?> constructor() {
-            Class<?>[] parameterTypes = new Class<?>[parameterTypeNames.length];
-            int index = 0;
-            for (String parameterTypeName : parameterTypeNames) {
-                if (PRIMITIVES.containsKey(parameterTypeName)) {
-                    parameterTypes[index++] = PRIMITIVES.get(parameterTypeName);
+            Class<?>[] resolvedParamTypes = new Class<?>[paramTypeNames.length];
+            int pos = 0;
+            for (String paramTypeName : paramTypeNames) {
+                if (PRIMITIVE_TYPES.containsKey(paramTypeName)) {
+                    resolvedParamTypes[pos++] = PRIMITIVE_TYPES.get(paramTypeName);
                 } else {
                     try {
-                        parameterTypes[index++] =
-                                Class.forName(parameterTypeName, false, type.getClassLoader());
-                    } catch (ClassNotFoundException e) {
+                        resolvedParamTypes[pos++] =
+                                Class.forName(paramTypeName, false, targetClass.getClassLoader());
+                    } catch (ClassNotFoundException ex) {
                         throw new MockitoException(
-                                "Could not find parameter of type " + parameterTypeName, e);
+                                "Could not find parameter of type " + paramTypeName, ex);
                     }
                 }
             }
             try {
-                return type.getDeclaredConstructor(parameterTypes);
-            } catch (NoSuchMethodException e) {
+                return targetClass.getDeclaredConstructor(resolvedParamTypes);
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
+                                Arrays.toString(resolvedParamTypes)),
+                    ex);
             }
         }
 
         @Override
         public List<?> arguments() {
-            return Collections.unmodifiableList(Arrays.asList(arguments));
+            return Collections.unmodifiableList(Arrays.asList(argsArray));
         }
     }
 }
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..2d1729ff7 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -16,18 +16,18 @@ import java.util.function.Function;
 
 public class InlineByteBuddyMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
-    private final InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
+    private final DelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
 
     public InlineByteBuddyMockMaker() {
         try {
-            inlineDelegateByteBuddyMockMaker = new InlineDelegateByteBuddyMockMaker();
+            inlineDelegateByteBuddyMockMaker = new DelegateByteBuddyMockMaker();
         } catch (NoClassDefFoundError e) {
             Reporter.missingByteBuddyDependency(e);
             throw e;
         }
     }
 
-    InlineByteBuddyMockMaker(InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
+    InlineByteBuddyMockMaker(DelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
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
+        return inlineDelegateByteBuddyMockMaker.createStaticClassMock(type, settings, handler);
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
+        inlineDelegateByteBuddyMockMaker.clearAllMocksAndCaches();
     }
 }
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
index 9069e50b8..d8747b5eb 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
@@ -14,7 +14,7 @@ import static org.mockito.Mockito.verify;
 
 public class InlineByteBuddyMockMakerTest extends TestBase {
 
-    @Mock private InlineDelegateByteBuddyMockMaker delegate;
+    @Mock private DelegateByteBuddyMockMaker delegate;
 
     @Test
     public void should_delegate_call() {
@@ -34,15 +34,15 @@ public class InlineByteBuddyMockMakerTest extends TestBase {
         mockMaker.clearAllMocks();
         mockMaker.clearAllCaches();
 
-        verify(delegate).createMock(creationSettings, handler);
-        verify(delegate).createStaticMock(Object.class, creationSettings, handler);
-        verify(delegate).createConstructionMock(Object.class, null, null, null);
+        verify(delegate).createMockInstance(creationSettings, handler);
+        verify(delegate).createStaticClassMock(Object.class, creationSettings, handler);
+        verify(delegate).createConstructionMockController(Object.class, null, null, null);
         verify(delegate).createMockType(creationSettings);
         verify(delegate).getHandler(this);
         verify(delegate).isTypeMockable(Object.class);
-        verify(delegate).resetMock(this, handler, creationSettings);
+        verify(delegate).resetMockInterceptor(this, handler, creationSettings);
         verify(delegate).clearMock(this);
         verify(delegate).clearAllMocks();
-        verify(delegate).clearAllCaches();
+        verify(delegate).clearAllMocksAndCaches();
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

