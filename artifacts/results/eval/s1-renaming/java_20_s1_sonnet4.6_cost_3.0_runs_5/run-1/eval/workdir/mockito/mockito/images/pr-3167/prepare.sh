#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout b6554b29ed6c204a0dd4b8a670877fe0ba2e808b

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyInlineMockMaker.java
similarity index 56%
rename from src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
rename to src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyInlineMockMaker.java
index 4cb0b40c0..5cb74f598 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyInlineMockMaker.java
@@ -100,12 +100,12 @@ import static org.mockito.internal.util.StringUtil.join;
  * support this feature.
  */
 @SuppressSignatureCheck
-class InlineDelegateByteBuddyMockMaker
+class ByteBuddyInlineMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
 
-    private static final Instrumentation INSTRUMENTATION;
+    private static final Instrumentation JVM_AGENT;
 
-    private static final Throwable INITIALIZATION_ERROR;
+    private static final Throwable INIT_FAILURE;
 
     static {
         Instrumentation instrumentation;
@@ -145,7 +145,7 @@ class InlineDelegateByteBuddyMockMaker
                     String source =
                             "org/mockito/internal/creation/bytebuddy/inject/MockMethodDispatcher";
                     InputStream inputStream =
-                            InlineDelegateByteBuddyMockMaker.class
+                            ByteBuddyInlineMockMaker.class
                                     .getClassLoader()
                                     .getResourceAsStream(source + ".raw");
                     if (inputStream == null) {
@@ -156,7 +156,7 @@ class InlineDelegateByteBuddyMockMaker
                                                 + ".raw",
                                         "",
                                         "The class loader responsible for looking up the resource: "
-                                                + InlineDelegateByteBuddyMockMaker.class
+                                                + ByteBuddyInlineMockMaker.class
                                                         .getClassLoader()));
                     }
                     outputStream.putNextEntry(new JarEntry(source + ".class"));
@@ -203,39 +203,39 @@ class InlineDelegateByteBuddyMockMaker
             instrumentation = null;
             initializationError = throwable;
         }
-        INSTRUMENTATION = instrumentation;
-        INITIALIZATION_ERROR = initializationError;
+        JVM_AGENT = instrumentation;
+        INIT_FAILURE = initializationError;
     }
 
-    private final BytecodeGenerator bytecodeGenerator;
+    private final BytecodeGenerator codeGenerator;
 
-    private final WeakConcurrentMap<Object, MockMethodInterceptor> mocks =
+    private final WeakConcurrentMap<Object, MockMethodInterceptor> interceptorMap =
             new WeakConcurrentMap<>(false);
 
-    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> mockedStatics =
+    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> staticInterceptors =
             new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
     private final DetachedThreadLocal<Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>>>
-            mockedConstruction = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
+        constructionInterceptors = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
-    private final ThreadLocal<Class<?>> currentMocking = ThreadLocal.withInitial(() -> null);
+    private final ThreadLocal<Class<?>> currentTargetType = ThreadLocal.withInitial(() -> null);
 
-    private final ThreadLocal<Object> currentSpied = new ThreadLocal<>();
+    private final ThreadLocal<Object> currentSpyInstance = new ThreadLocal<>();
 
-    InlineDelegateByteBuddyMockMaker() {
-        if (INITIALIZATION_ERROR != null) {
-            String detail;
+    ByteBuddyInlineMockMaker() {
+        if (INIT_FAILURE != null) {
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
+                    if (INIT_FAILURE instanceof NoClassDefFoundError
+                            && INIT_FAILURE.getMessage() != null
+                            && INIT_FAILURE
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
+                } catch (Throwable suppressed) {
+                    messageDetail =
                             "It appears as if you are running an incomplete JVM installation that might not support all tooling APIs";
                 }
             }
@@ -260,180 +260,178 @@ class InlineDelegateByteBuddyMockMaker
                     join(
                             "Could not initialize inline Byte Buddy mock maker.",
                             "",
-                            detail,
+                        messageDetail,
                             Platform.describe()),
-                    INITIALIZATION_ERROR);
+                INIT_FAILURE);
         }
 
-        ThreadLocal<Class<?>> currentConstruction = new ThreadLocal<>();
-        ThreadLocal<Boolean> isSuspended = ThreadLocal.withInitial(() -> false);
-        Predicate<Class<?>> isCallFromSubclassConstructor = StackWalkerChecker.orFallback();
-        Predicate<Class<?>> isMockConstruction =
-                type -> {
-                    if (isSuspended.get()) {
+        ThreadLocal<Class<?>> currentCtorType = new ThreadLocal<>();
+        ThreadLocal<Boolean> suspendedFlag = ThreadLocal.withInitial(() -> false);
+        Predicate<Class<?>> fromSubclassCtorPredicate = StackWalkerChecker.orFallback();
+        Predicate<Class<?>> constructionPredicate =
+            targetClass -> {
+                    if (suspendedFlag.get()) {
                         return false;
-                    } else if ((currentMocking.get() != null
-                                    && type.isAssignableFrom(currentMocking.get()))
-                            || currentConstruction.get() != null) {
+                    } else if ((currentTargetType.get() != null
+                                    && targetClass.isAssignableFrom(currentTargetType.get()))
+                            || currentCtorType.get() != null) {
                         return true;
                     }
-                    Map<Class<?>, ?> interceptors = mockedConstruction.get();
-                    if (interceptors != null && interceptors.containsKey(type)) {
+                    Map<Class<?>, ?> typeInterceptors = constructionInterceptors.get();
+                    if (typeInterceptors != null && typeInterceptors.containsKey(targetClass)) {
                         // We only initiate a construction mock, if the call originates from an
                         // un-mocked (as suppression is not enabled) subclass constructor.
-                        if (isCallFromSubclassConstructor.test(type)) {
+                        if (fromSubclassCtorPredicate.test(targetClass)) {
                             return false;
                         }
-                        currentConstruction.set(type);
+                        currentCtorType.set(targetClass);
                         return true;
                     } else {
                         return false;
                     }
                 };
-        ConstructionCallback onConstruction =
-                (type, object, arguments, parameterTypeNames) -> {
-                    if (currentMocking.get() != null) {
-                        Object spy = currentSpied.get();
-                        if (spy == null) {
+        ConstructionCallback constructionCallback =
+                (targetClass, targetInstance, callArgs, paramTypeNames) -> {
+                    if (currentTargetType.get() != null) {
+                        Object spyInstance = currentSpyInstance.get();
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
+                                                + targetInstance.getClass().getName(),
+                                        targetInstance instanceof Throwable ? (Throwable) targetInstance : null);
                             } finally {
-                                isSuspended.set(false);
+                                suspendedFlag.set(false);
                             }
                         }
-                    } else if (currentConstruction.get() != type) {
+                    } else if (currentCtorType.get() != targetClass) {
                         return null;
                     }
-                    currentConstruction.remove();
-                    isSuspended.set(true);
+                    currentCtorType.remove();
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
+                        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> typeInterceptors =
+                                constructionInterceptors.get();
+                        if (typeInterceptors != null) {
+                            BiConsumer<Object, MockedConstruction.Context> handler =
+                                    typeInterceptors.get(targetClass);
+                            if (handler != null) {
+                                handler.accept(
+                                    targetInstance,
+                                        new InlineMockConstructionContext(
+                                            callArgs, targetInstance.getClass(), paramTypeNames));
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
+                            JVM_AGENT,
+                            interceptorMap,
+                            staticInterceptors,
+                            constructionPredicate,
+                            constructionCallback),
                         true);
     }
 
-    @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return doCreateMock(settings, handler, false);
+    public <T> T createInlineMock(MockCreationSettings<T> creationSettings, MockHandler mockHandlerImpl) {
+        return createMockInstance(creationSettings, mockHandlerImpl, false);
     }
 
-    @Override
-    public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T object) {
-        if (object == null) {
+    public <T> Optional<T> createSpyInstance(
+        MockCreationSettings<T> creationSettings, MockHandler mockHandlerImpl, T targetInstance) {
+        if (targetInstance == null) {
             throw new MockitoConfigurationException("Spy instance must not be null");
         }
-        currentSpied.set(object);
+        currentSpyInstance.set(targetInstance);
         try {
-            return Optional.ofNullable(doCreateMock(settings, handler, true));
+            return Optional.ofNullable(createMockInstance(creationSettings, mockHandlerImpl, true));
         } finally {
-            currentSpied.remove();
+            currentSpyInstance.remove();
         }
     }
 
-    private <T> T doCreateMock(
-            MockCreationSettings<T> settings,
-            MockHandler handler,
-            boolean nullOnNonInlineConstruction) {
-        Class<? extends T> type = createMockType(settings);
+    private <T> T createMockInstance(
+            MockCreationSettings<T> creationSettings,
+            MockHandler mockHandlerImpl,
+            boolean returnNullForNonInline) {
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
+                } catch (InstantiationException suppressed) {
+                    if (returnNullForNonInline) {
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
+            MockMethodInterceptor methodInterceptorImpl =
+                    new MockMethodInterceptor(mockHandlerImpl, creationSettings);
+            interceptorMap.put(createdInstance, methodInterceptorImpl);
+            if (createdInstance instanceof MockAccess) {
+                ((MockAccess) createdInstance).setMockitoInterceptor(methodInterceptorImpl);
             }
-            mocks.expungeStaleEntries();
-            return instance;
-        } catch (InstantiationException e) {
+            interceptorMap.expungeStaleEntries();
+            return createdInstance;
+        } catch (InstantiationException instantiationEx) {
             throw new MockitoException(
-                    "Unable to create mock instance of type '" + type.getSimpleName() + "'", e);
+                    "Unable to create mock instance of type '" + targetClass.getSimpleName() + "'", instantiationEx);
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
+        } catch (Exception generationException) {
+            throw formatMockCreationFailure(creationSettings, generationException);
         }
     }
 
-    private <T> RuntimeException prettifyFailure(
-            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
-        if (mockFeatures.getTypeToMock().isArray()) {
+    private <T> RuntimeException formatMockCreationFailure(
+        MockCreationSettings<T> features, Exception generationException) {
+        if (features.getTypeToMock().isArray()) {
             throw new MockitoException(
-                    join("Arrays cannot be mocked: " + mockFeatures.getTypeToMock() + ".", ""),
-                    generationFailed);
+                    join("Arrays cannot be mocked: " + features.getTypeToMock() + ".", ""),
+                generationException);
         }
-        if (Modifier.isFinal(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isFinal(features.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + features.getTypeToMock() + ".",
                             "Can not mock final classes with the following settings :",
                             " - explicit serialization (e.g. withSettings().serializable())",
                             " - extra interfaces (e.g. withSettings().extraInterfaces(...))",
@@ -441,23 +439,23 @@ class InlineDelegateByteBuddyMockMaker
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             "",
-                            "Underlying exception : " + generationFailed),
-                    generationFailed);
+                            "Underlying exception : " + generationException),
+                generationException);
         }
-        if (Modifier.isPrivate(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isPrivate(features.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + features.getTypeToMock() + ".",
                             "Most likely it is a private class that is not visible by Mockito",
                             "",
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             ""),
-                    generationFailed);
+                generationException);
         }
         throw new MockitoException(
                 join(
-                        "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                        "Mockito cannot mock this class: " + features.getTypeToMock() + ".",
                         "",
                         "If you're not sure why you're getting this error, please open an issue on GitHub.",
                         "",
@@ -471,81 +469,79 @@ class InlineDelegateByteBuddyMockMaker
                         "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                         "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                         "",
-                        "Underlying exception : " + generationFailed),
-                generationFailed);
+                        "Underlying exception : " + generationException),
+            generationException);
     }
 
     @Override
-    public MockHandler getHandler(Object mock) {
-        MockMethodInterceptor interceptor;
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            interceptor = interceptors != null ? interceptors.get(mock) : null;
+    public MockHandler getHandler(Object candidate) {
+        MockMethodInterceptor handler;
+        if (candidate instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> typeInterceptors = staticInterceptors.get();
+            handler = typeInterceptors != null ? typeInterceptors.get(candidate) : null;
         } else {
-            interceptor = mocks.get(mock);
+            handler = interceptorMap.get(candidate);
         }
-        if (interceptor == null) {
+        if (handler == null) {
             return null;
         } else {
-            return interceptor.handler;
+            return handler.handler;
         }
     }
 
-    @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
-        MockMethodInterceptor mockMethodInterceptor =
-                new MockMethodInterceptor(newHandler, settings);
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            if (interceptors == null || !interceptors.containsKey(mock)) {
+    public void resetMockInstance(Object candidate, MockHandler replacementHandler, MockCreationSettings creationSettings) {
+        MockMethodInterceptor methodInterceptorImpl =
+                new MockMethodInterceptor(replacementHandler, creationSettings);
+        if (candidate instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> typeInterceptors = staticInterceptors.get();
+            if (typeInterceptors == null || !typeInterceptors.containsKey(candidate)) {
                 throw new MockitoException(
                         "Cannot reset "
-                                + mock
+                                + candidate
                                 + " which is not currently registered as a static mock");
             }
-            interceptors.put((Class<?>) mock, mockMethodInterceptor);
+            typeInterceptors.put((Class<?>) candidate, methodInterceptorImpl);
         } else {
-            if (!mocks.containsKey(mock)) {
+            if (!interceptorMap.containsKey(candidate)) {
                 throw new MockitoException(
-                        "Cannot reset " + mock + " which is not currently registered as a mock");
+                        "Cannot reset " + candidate + " which is not currently registered as a mock");
             }
-            mocks.put(mock, mockMethodInterceptor);
-            if (mock instanceof MockAccess) {
-                ((MockAccess) mock).setMockitoInterceptor(mockMethodInterceptor);
+            interceptorMap.put(candidate, methodInterceptorImpl);
+            if (candidate instanceof MockAccess) {
+                ((MockAccess) candidate).setMockitoInterceptor(methodInterceptorImpl);
             }
-            mocks.expungeStaleEntries();
+            interceptorMap.expungeStaleEntries();
         }
     }
 
-    @Override
-    public void clearAllCaches() {
+    public void clearCaches() {
         clearAllMocks();
-        bytecodeGenerator.clearAllCaches();
+        codeGenerator.clearAllCaches();
     }
 
     @Override
-    public void clearMock(Object mock) {
-        if (mock instanceof Class<?>) {
-            for (Map<Class<?>, ?> entry : mockedStatics.getBackingMap().target.values()) {
-                entry.remove(mock);
+    public void clearMock(Object candidate) {
+        if (candidate instanceof Class<?>) {
+            for (Map<Class<?>, ?> mapEntry : staticInterceptors.getBackingMap().target.values()) {
+                mapEntry.remove(candidate);
             }
         } else {
-            mocks.remove(mock);
+            interceptorMap.remove(candidate);
         }
     }
 
     @Override
     public void clearAllMocks() {
-        mockedStatics.getBackingMap().clear();
-        mocks.clear();
+        staticInterceptors.getBackingMap().clear();
+        interceptorMap.clear();
     }
 
     @Override
-    public TypeMockability isTypeMockable(final Class<?> type) {
+    public TypeMockability isTypeMockable(final Class<?> targetClass) {
         return new TypeMockability() {
             @Override
             public boolean mockable() {
-                return INSTRUMENTATION.isModifiableClass(type) && !EXCLUDES.contains(type);
+                return JVM_AGENT.isModifiableClass(targetClass) && !EXCLUDES.contains(targetClass);
             }
 
             @Override
@@ -553,10 +549,10 @@ class InlineDelegateByteBuddyMockMaker
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
@@ -564,160 +560,158 @@ class InlineDelegateByteBuddyMockMaker
         };
     }
 
-    @Override
-    public <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
-        if (type == ConcurrentHashMap.class) {
+    public <T> StaticMockControl<T> createInlineStaticMock(
+        Class<T> targetClass, MockCreationSettings<T> creationSettings, MockHandler mockHandlerImpl) {
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
+        Map<Class<?>, MockMethodInterceptor> typeInterceptors = staticInterceptors.get();
+        if (typeInterceptors == null) {
+            typeInterceptors = new WeakHashMap<>();
+            staticInterceptors.set(typeInterceptors);
         }
-        mockedStatics.getBackingMap().expungeStaleEntries();
+        staticInterceptors.getBackingMap().expungeStaleEntries();
 
-        return new InlineStaticMockControl<>(type, interceptors, settings, handler);
+        return new InlineStaticMockController<>(targetClass, typeInterceptors, creationSettings, mockHandlerImpl);
     }
 
-    @Override
-    public <T> ConstructionMockControl<T> createConstructionMock(
-            Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
-            Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
-            MockedConstruction.MockInitializer<T> mockInitializer) {
-        if (type == Object.class) {
+    public <T> ConstructionMockControl<T> createInlineConstructionMock(
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
+        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> typeInterceptors =
+                constructionInterceptors.get();
+        if (typeInterceptors == null) {
+            typeInterceptors = new WeakHashMap<>();
+            constructionInterceptors.set(typeInterceptors);
         }
-        mockedConstruction.getBackingMap().expungeStaleEntries();
+        constructionInterceptors.getBackingMap().expungeStaleEntries();
 
-        return new InlineConstructionMockControl<>(
-                type, settingsFactory, handlerFactory, mockInitializer, interceptors);
+        return new InlineConstructionMockController<>(
+            targetClass, settingsProvider, handlerProvider, initializer, typeInterceptors);
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
+        Class<?>[] argTypes = chosenConstructor.getParameterTypes();
+        Object[] callArgs = new Object[argTypes.length];
+        int pos = 0;
+        for (Class<?> targetClass : argTypes) {
+            callArgs[pos++] = makeDefaultArgument(targetClass);
         }
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor memberAccessorImpl = Plugins.getMemberAccessor();
         try {
             return (T)
-                    accessor.newInstance(
-                            selected,
-                            callback -> {
-                                currentMocking.set(cls);
+                    memberAccessorImpl.newInstance(
+                        chosenConstructor,
+                        constructionDispatcherImpl -> {
+                                currentTargetType.set(clazz);
                                 try {
-                                    return callback.newInstance();
+                                    return constructionDispatcherImpl.newInstance();
                                 } finally {
-                                    currentMocking.remove();
+                                    currentTargetType.remove();
                                 }
                             },
-                            arguments);
-        } catch (Exception e) {
-            throw new InstantiationException("Could not instantiate " + cls.getName(), e);
+                        callArgs);
+        } catch (Exception instantiationEx) {
+            throw new InstantiationException("Could not instantiate " + clazz.getName(), instantiationEx);
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
+        private final Map<Class<?>, MockMethodInterceptor> typeInterceptors;
 
-        private final MockCreationSettings<T> settings;
+        private final MockCreationSettings<T> creationSettings;
 
-        private final MockHandler handler;
+        private final MockHandler mockHandlerImpl;
 
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
+                Map<Class<?>, MockMethodInterceptor> typeInterceptors,
+                MockCreationSettings<T> creationSettings,
+                MockHandler mockHandlerImpl) {
+            this.targetClass = targetClass;
+            this.typeInterceptors = typeInterceptors;
+            this.creationSettings = creationSettings;
+            this.mockHandlerImpl = mockHandlerImpl;
         }
 
         @Override
         public Class<T> getType() {
-            return type;
+            return targetClass;
         }
 
         @Override
         public void enable() {
-            if (interceptors.putIfAbsent(type, new MockMethodInterceptor(handler, settings))
+            if (typeInterceptors.putIfAbsent(targetClass, new MockMethodInterceptor(mockHandlerImpl, creationSettings))
                     != null) {
                 throw new MockitoException(
                         join(
                                 "For "
-                                        + type.getName()
+                                        + targetClass.getName()
                                         + ", static mocking is already registered in the current thread",
                                 "",
                                 "To create a new mock, the existing static mock registration must be deregistered"));
@@ -726,79 +720,79 @@ class InlineDelegateByteBuddyMockMaker
 
         @Override
         public void disable() {
-            if (interceptors.remove(type) == null) {
+            if (typeInterceptors.remove(targetClass) == null) {
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
+        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> typeInterceptors;
 
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
+                Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> typeInterceptors) {
+            this.targetClass = targetClass;
+            this.settingsProvider = settingsProvider;
+            this.handlerProvider = handlerProvider;
+            this.initializer = initializer;
+            this.typeInterceptors = typeInterceptors;
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
+            if (typeInterceptors.putIfAbsent(
+                targetClass,
+                            (targetInstance, callContext) -> {
+                                ((InlineMockConstructionContext) callContext).instanceCount = ++instanceCount;
+                                MockMethodInterceptor handler =
                                         new MockMethodInterceptor(
-                                                handlerFactory.apply(context),
-                                                settingsFactory.apply(context));
-                                mocks.put(object, interceptor);
+                                                handlerProvider.apply(callContext),
+                                                settingsProvider.apply(callContext));
+                                interceptorMap.put(targetInstance, handler);
                                 try {
                                     @SuppressWarnings("unchecked")
-                                    T cast = (T) object;
-                                    mockInitializer.prepare(cast, context);
-                                } catch (Throwable t) {
-                                    mocks.remove(object); // TODO: filter stack trace?
+                                    T typed = (T) targetInstance;
+                                    initializer.prepare(typed, callContext);
+                                } catch (Throwable throwable) {
+                                    interceptorMap.remove(targetInstance); // TODO: filter stack trace?
                                     throw new MockitoException(
-                                            "Could not initialize mocked construction", t);
+                                            "Could not initialize mocked construction", throwable);
                                 }
-                                all.add(object);
+                                allInstances.add(targetInstance);
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
@@ -807,99 +801,99 @@ class InlineDelegateByteBuddyMockMaker
 
         @Override
         public void disable() {
-            if (interceptors.remove(type) == null) {
+            if (typeInterceptors.remove(targetClass) == null) {
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
+    private static class InlineMockConstructionContext implements MockedConstruction.Context {
 
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
+        private final Object[] callArgs;
+        private final Class<?> targetClass;
+        private final String[] paramTypeNames;
 
-        private InlineConstructionMockContext(
-                Object[] arguments, Class<?> type, String[] parameterTypeNames) {
-            this.arguments = arguments;
-            this.type = type;
-            this.parameterTypeNames = parameterTypeNames;
+        private InlineMockConstructionContext(
+            Object[] callArgs, Class<?> targetClass, String[] paramTypeNames) {
+            this.callArgs = callArgs;
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
+            Class<?>[] resolvedParameterTypes = new Class<?>[paramTypeNames.length];
+            int pos = 0;
+            for (String paramTypeName : paramTypeNames) {
+                if (PRIMITIVE_TYPES.containsKey(paramTypeName)) {
+                    resolvedParameterTypes[pos++] = PRIMITIVE_TYPES.get(paramTypeName);
                 } else {
                     try {
-                        parameterTypes[index++] =
-                                Class.forName(parameterTypeName, false, type.getClassLoader());
-                    } catch (ClassNotFoundException e) {
+                        resolvedParameterTypes[pos++] =
+                                Class.forName(paramTypeName, false, targetClass.getClassLoader());
+                    } catch (ClassNotFoundException instantiationEx) {
                         throw new MockitoException(
-                                "Could not find parameter of type " + parameterTypeName, e);
+                                "Could not find parameter of type " + paramTypeName, instantiationEx);
                     }
                 }
             }
             try {
-                return type.getDeclaredConstructor(parameterTypes);
-            } catch (NoSuchMethodException e) {
+                return targetClass.getDeclaredConstructor(resolvedParameterTypes);
+            } catch (NoSuchMethodException instantiationEx) {
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
+                                Arrays.toString(resolvedParameterTypes)),
+                    instantiationEx);
             }
         }
 
         @Override
         public List<?> arguments() {
-            return Collections.unmodifiableList(Arrays.asList(arguments));
+            return Collections.unmodifiableList(Arrays.asList(callArgs));
         }
     }
 }
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..55bd5c42a 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -16,18 +16,18 @@ import java.util.function.Function;
 
 public class InlineByteBuddyMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
-    private final InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
+    private final ByteBuddyInlineMockMaker inlineDelegateByteBuddyMockMaker;
 
     public InlineByteBuddyMockMaker() {
         try {
-            inlineDelegateByteBuddyMockMaker = new InlineDelegateByteBuddyMockMaker();
+            inlineDelegateByteBuddyMockMaker = new ByteBuddyInlineMockMaker();
         } catch (NoClassDefFoundError e) {
             Reporter.missingByteBuddyDependency(e);
             throw e;
         }
     }
 
-    InlineByteBuddyMockMaker(InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
+    InlineByteBuddyMockMaker(ByteBuddyInlineMockMaker inlineDelegateByteBuddyMockMaker) {
         this.inlineDelegateByteBuddyMockMaker = inlineDelegateByteBuddyMockMaker;
     }
 
@@ -53,13 +53,13 @@ public class InlineByteBuddyMockMaker
 
     @Override
     public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return inlineDelegateByteBuddyMockMaker.createMock(settings, handler);
+        return inlineDelegateByteBuddyMockMaker.createInlineMock(settings, handler);
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
+        inlineDelegateByteBuddyMockMaker.resetMockInstance(mock, newHandler, settings);
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
+        return inlineDelegateByteBuddyMockMaker.createInlineConstructionMock(
                 type, settingsFactory, handlerFactory, mockInitializer);
     }
 
     @Override
     public void clearAllCaches() {
-        inlineDelegateByteBuddyMockMaker.clearAllCaches();
+        inlineDelegateByteBuddyMockMaker.clearCaches();
     }
 }
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
index 9069e50b8..78419b4b3 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
@@ -14,7 +14,7 @@ import static org.mockito.Mockito.verify;
 
 public class InlineByteBuddyMockMakerTest extends TestBase {
 
-    @Mock private InlineDelegateByteBuddyMockMaker delegate;
+    @Mock private ByteBuddyInlineMockMaker delegate;
 
     @Test
     public void should_delegate_call() {
@@ -34,15 +34,15 @@ public class InlineByteBuddyMockMakerTest extends TestBase {
         mockMaker.clearAllMocks();
         mockMaker.clearAllCaches();
 
-        verify(delegate).createMock(creationSettings, handler);
-        verify(delegate).createStaticMock(Object.class, creationSettings, handler);
-        verify(delegate).createConstructionMock(Object.class, null, null, null);
+        verify(delegate).createInlineMock(creationSettings, handler);
+        verify(delegate).createInlineStaticMock(Object.class, creationSettings, handler);
+        verify(delegate).createInlineConstructionMock(Object.class, null, null, null);
         verify(delegate).createMockType(creationSettings);
         verify(delegate).getHandler(this);
         verify(delegate).isTypeMockable(Object.class);
-        verify(delegate).resetMock(this, handler, creationSettings);
+        verify(delegate).resetMockInstance(this, handler, creationSettings);
         verify(delegate).clearMock(this);
         verify(delegate).clearAllMocks();
-        verify(delegate).clearAllCaches();
+        verify(delegate).clearCaches();
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

