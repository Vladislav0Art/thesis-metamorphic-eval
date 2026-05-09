#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout b6554b29ed6c204a0dd4b8a670877fe0ba2e808b

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..c7b923bd7 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -16,18 +16,18 @@ import java.util.function.Function;
 
 public class InlineByteBuddyMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
-    private final InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
+    private final InlineDelegateByteBuddyMockFactory inlineDelegateByteBuddyMockMaker;
 
     public InlineByteBuddyMockMaker() {
         try {
-            inlineDelegateByteBuddyMockMaker = new InlineDelegateByteBuddyMockMaker();
+            inlineDelegateByteBuddyMockMaker = new InlineDelegateByteBuddyMockFactory();
         } catch (NoClassDefFoundError e) {
             Reporter.missingByteBuddyDependency(e);
             throw e;
         }
     }
 
-    InlineByteBuddyMockMaker(InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
+    InlineByteBuddyMockMaker(InlineDelegateByteBuddyMockFactory inlineDelegateByteBuddyMockMaker) {
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
+        return inlineDelegateByteBuddyMockMaker.createMockConstruction(
                 type, settingsFactory, handlerFactory, mockInitializer);
     }
 
     @Override
     public void clearAllCaches() {
-        inlineDelegateByteBuddyMockMaker.clearAllCaches();
+        inlineDelegateByteBuddyMockMaker.clearCaches();
     }
 }
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockFactory.java
similarity index 57%
rename from src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
rename to src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockFactory.java
index 4cb0b40c0..a4c6f0cbd 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockFactory.java
@@ -100,12 +100,12 @@ import static org.mockito.internal.util.StringUtil.join;
  * support this feature.
  */
 @SuppressSignatureCheck
-class InlineDelegateByteBuddyMockMaker
+class InlineDelegateByteBuddyMockFactory
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
 
-    private static final Instrumentation INSTRUMENTATION;
+    private static final Instrumentation JAVA_AGENT;
 
-    private static final Throwable INITIALIZATION_ERROR;
+    private static final Throwable INIT_FAILURE;
 
     static {
         Instrumentation instrumentation;
@@ -145,7 +145,7 @@ class InlineDelegateByteBuddyMockMaker
                     String source =
                             "org/mockito/internal/creation/bytebuddy/inject/MockMethodDispatcher";
                     InputStream inputStream =
-                            InlineDelegateByteBuddyMockMaker.class
+                            InlineDelegateByteBuddyMockFactory.class
                                     .getClassLoader()
                                     .getResourceAsStream(source + ".raw");
                     if (inputStream == null) {
@@ -156,7 +156,7 @@ class InlineDelegateByteBuddyMockMaker
                                                 + ".raw",
                                         "",
                                         "The class loader responsible for looking up the resource: "
-                                                + InlineDelegateByteBuddyMockMaker.class
+                                                + InlineDelegateByteBuddyMockFactory.class
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
+        INIT_FAILURE = initializationError;
     }
 
-    private final BytecodeGenerator bytecodeGenerator;
+    private final BytecodeGenerator classGenerator;
 
-    private final WeakConcurrentMap<Object, MockMethodInterceptor> mocks =
+    private final WeakConcurrentMap<Object, MockMethodInterceptor> interceptorMap =
             new WeakConcurrentMap<>(false);
 
-    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> mockedStatics =
+    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> staticInterceptorMap =
             new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
     private final DetachedThreadLocal<Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>>>
-            mockedConstruction = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
+        constructionCallbackLocal = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
-    private final ThreadLocal<Class<?>> currentMocking = ThreadLocal.withInitial(() -> null);
+    private final ThreadLocal<Class<?>> currentTargetClass = ThreadLocal.withInitial(() -> null);
 
-    private final ThreadLocal<Object> currentSpied = new ThreadLocal<>();
+    private final ThreadLocal<Object> currentSubject = new ThreadLocal<>();
 
-    InlineDelegateByteBuddyMockMaker() {
-        if (INITIALIZATION_ERROR != null) {
-            String detail;
+    InlineDelegateByteBuddyMockFactory() {
+        if (INIT_FAILURE != null) {
+            String description;
             if (PlatformUtils.isAndroidPlatform() || PlatformUtils.isProbablyTermuxEnvironment()) {
-                detail =
+                description =
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
+                        description =
                                 join(
                                         "It seems like you are running Mockito with an incomplete or inconsistent class path. Byte Buddy Agent could not be loaded.",
                                         "",
@@ -245,14 +245,14 @@ class InlineDelegateByteBuddyMockMaker
                                     .getMethod("getSystemJavaCompiler")
                                     .invoke(null)
                             == null) {
-                        detail =
+                        description =
                                 "It appears as if you are running on a JRE. Either install a JDK or add JNA to the class path.";
                     } else {
-                        detail =
+                        description =
                                 "It appears as if your JDK does not supply a working agent attachment mechanism.";
                     }
-                } catch (Throwable ignored) {
-                    detail =
+                } catch (Throwable cause) {
+                    description =
                             "It appears as if you are running an incomplete JVM installation that might not support all tooling APIs";
                 }
             }
@@ -260,180 +260,178 @@ class InlineDelegateByteBuddyMockMaker
                     join(
                             "Could not initialize inline Byte Buddy mock maker.",
                             "",
-                            detail,
+                        description,
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
+        ThreadLocal<Class<?>> constructionTypeLocal = new ThreadLocal<>();
+        ThreadLocal<Boolean> suspendedFlag = ThreadLocal.withInitial(() -> false);
+        Predicate<Class<?>> subclassCtorChecker = StackWalkerChecker.orFallback();
+        Predicate<Class<?>> constructionPredicate =
+            clazz -> {
+                    if (suspendedFlag.get()) {
                         return false;
-                    } else if ((currentMocking.get() != null
-                                    && type.isAssignableFrom(currentMocking.get()))
-                            || currentConstruction.get() != null) {
+                    } else if ((currentTargetClass.get() != null
+                                    && clazz.isAssignableFrom(currentTargetClass.get()))
+                            || constructionTypeLocal.get() != null) {
                         return true;
                     }
-                    Map<Class<?>, ?> interceptors = mockedConstruction.get();
-                    if (interceptors != null && interceptors.containsKey(type)) {
+                    Map<Class<?>, ?> interceptorMap = constructionCallbackLocal.get();
+                    if (interceptorMap != null && interceptorMap.containsKey(clazz)) {
                         // We only initiate a construction mock, if the call originates from an
                         // un-mocked (as suppression is not enabled) subclass constructor.
-                        if (isCallFromSubclassConstructor.test(type)) {
+                        if (subclassCtorChecker.test(clazz)) {
                             return false;
                         }
-                        currentConstruction.set(type);
+                        constructionTypeLocal.set(clazz);
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
+                (clazz, instance, args, typeNameArray) -> {
+                    if (currentTargetClass.get() != null) {
+                        Object partialInstance = currentSubject.get();
+                        if (partialInstance == null) {
                             return null;
-                        } else if (type.isInstance(spy)) {
-                            return spy;
+                        } else if (clazz.isInstance(partialInstance)) {
+                            return partialInstance;
                         } else {
-                            isSuspended.set(true);
+                            suspendedFlag.set(true);
                             try {
                                 // Unexpected construction of non-spied object
                                 throw new MockitoException(
                                         "Unexpected spy for "
-                                                + type.getName()
+                                                + clazz.getName()
                                                 + " on instance of "
-                                                + object.getClass().getName(),
-                                        object instanceof Throwable ? (Throwable) object : null);
+                                                + instance.getClass().getName(),
+                                        instance instanceof Throwable ? (Throwable) instance : null);
                             } finally {
-                                isSuspended.set(false);
+                                suspendedFlag.set(false);
                             }
                         }
-                    } else if (currentConstruction.get() != type) {
+                    } else if (constructionTypeLocal.get() != clazz) {
                         return null;
                     }
-                    currentConstruction.remove();
-                    isSuspended.set(true);
+                    constructionTypeLocal.remove();
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
+                                constructionCallbackLocal.get();
+                        if (interceptorMap != null) {
+                            BiConsumer<Object, MockedConstruction.Context> constructionHandler =
+                                    interceptorMap.get(clazz);
+                            if (constructionHandler != null) {
+                                constructionHandler.accept(
+                                    instance,
+                                        new InlineConstructorMockContext(
+                                            args, instance.getClass(), typeNameArray));
                             }
                         }
                     } finally {
-                        isSuspended.set(false);
+                        suspendedFlag.set(false);
                     }
                     return null;
                 };
 
-        bytecodeGenerator =
+        classGenerator =
                 new TypeCachingBytecodeGenerator(
                         new InlineBytecodeGenerator(
-                                INSTRUMENTATION,
-                                mocks,
-                                mockedStatics,
-                                isMockConstruction,
-                                onConstruction),
+                            JAVA_AGENT,
+                            interceptorMap,
+                            staticInterceptorMap,
+                            constructionPredicate,
+                            constructionCallback),
                         true);
     }
 
-    @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return doCreateMock(settings, handler, false);
+    public <T> T createMockInstance(MockCreationSettings<T> creationSettings, MockHandler invocationHandler) {
+        return createMockInstance(creationSettings, invocationHandler, false);
     }
 
-    @Override
-    public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T object) {
-        if (object == null) {
+    public <T> Optional<T> createSpyInstance(
+        MockCreationSettings<T> creationSettings, MockHandler invocationHandler, T instance) {
+        if (instance == null) {
             throw new MockitoConfigurationException("Spy instance must not be null");
         }
-        currentSpied.set(object);
+        currentSubject.set(instance);
         try {
-            return Optional.ofNullable(doCreateMock(settings, handler, true));
+            return Optional.ofNullable(createMockInstance(creationSettings, invocationHandler, true));
         } finally {
-            currentSpied.remove();
+            currentSubject.remove();
         }
     }
 
-    private <T> T doCreateMock(
-            MockCreationSettings<T> settings,
-            MockHandler handler,
-            boolean nullOnNonInlineConstruction) {
-        Class<? extends T> type = createMockType(settings);
+    private <T> T createMockInstance(
+            MockCreationSettings<T> creationSettings,
+            MockHandler invocationHandler,
+            boolean returnNullOnNonInline) {
+        Class<? extends T> clazz = createMockType(creationSettings);
 
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
+                                .newInstance(clazz);
             } else {
                 try {
                     // We attempt to use the "native" mock maker first that avoids
                     // Objenesis and Unsafe
-                    instance = newInstance(type);
-                } catch (InstantiationException ignored) {
-                    if (nullOnNonInlineConstruction) {
+                    createdInstance = newInstance(clazz);
+                } catch (InstantiationException cause) {
+                    if (returnNullOnNonInline) {
                         return null;
                     }
-                    Instantiator instantiator =
-                            Plugins.getInstantiatorProvider().getInstantiator(settings);
-                    instance = instantiator.newInstance(type);
+                    Instantiator objectInstantiator =
+                            Plugins.getInstantiatorProvider().getInstantiator(creationSettings);
+                    createdInstance = objectInstantiator.newInstance(clazz);
                 }
             }
-            MockMethodInterceptor mockMethodInterceptor =
-                    new MockMethodInterceptor(handler, settings);
-            mocks.put(instance, mockMethodInterceptor);
-            if (instance instanceof MockAccess) {
-                ((MockAccess) instance).setMockitoInterceptor(mockMethodInterceptor);
+            MockMethodInterceptor methodInterceptor =
+                    new MockMethodInterceptor(invocationHandler, creationSettings);
+            interceptorMap.put(createdInstance, methodInterceptor);
+            if (createdInstance instanceof MockAccess) {
+                ((MockAccess) createdInstance).setMockitoInterceptor(methodInterceptor);
             }
-            mocks.expungeStaleEntries();
-            return instance;
-        } catch (InstantiationException e) {
+            interceptorMap.expungeStaleEntries();
+            return createdInstance;
+        } catch (InstantiationException instantiationException) {
             throw new MockitoException(
-                    "Unable to create mock instance of type '" + type.getSimpleName() + "'", e);
+                    "Unable to create mock instance of type '" + clazz.getSimpleName() + "'", instantiationException);
         }
     }
 
     @Override
-    public <T> Class<? extends T> createMockType(MockCreationSettings<T> settings) {
+    public <T> Class<? extends T> createMockType(MockCreationSettings<T> creationSettings) {
         try {
-            return bytecodeGenerator.mockClass(
+            return classGenerator.mockClass(
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
+        MockCreationSettings<T> featuresSettings, Exception generationError) {
+        if (featuresSettings.getTypeToMock().isArray()) {
             throw new MockitoException(
-                    join("Arrays cannot be mocked: " + mockFeatures.getTypeToMock() + ".", ""),
-                    generationFailed);
+                    join("Arrays cannot be mocked: " + featuresSettings.getTypeToMock() + ".", ""),
+                generationError);
         }
-        if (Modifier.isFinal(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isFinal(featuresSettings.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + featuresSettings.getTypeToMock() + ".",
                             "Can not mock final classes with the following settings :",
                             " - explicit serialization (e.g. withSettings().serializable())",
                             " - extra interfaces (e.g. withSettings().extraInterfaces(...))",
@@ -441,23 +439,23 @@ class InlineDelegateByteBuddyMockMaker
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             "",
-                            "Underlying exception : " + generationFailed),
-                    generationFailed);
+                            "Underlying exception : " + generationError),
+                generationError);
         }
-        if (Modifier.isPrivate(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isPrivate(featuresSettings.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + featuresSettings.getTypeToMock() + ".",
                             "Most likely it is a private class that is not visible by Mockito",
                             "",
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             ""),
-                    generationFailed);
+                generationError);
         }
         throw new MockitoException(
                 join(
-                        "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                        "Mockito cannot mock this class: " + featuresSettings.getTypeToMock() + ".",
                         "",
                         "If you're not sure why you're getting this error, please open an issue on GitHub.",
                         "",
@@ -471,81 +469,79 @@ class InlineDelegateByteBuddyMockMaker
                         "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                         "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                         "",
-                        "Underlying exception : " + generationFailed),
-                generationFailed);
+                        "Underlying exception : " + generationError),
+            generationError);
     }
 
     @Override
-    public MockHandler getHandler(Object mock) {
-        MockMethodInterceptor interceptor;
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            interceptor = interceptors != null ? interceptors.get(mock) : null;
+    public MockHandler getHandler(Object target) {
+        MockMethodInterceptor constructionHandler;
+        if (target instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptorMap = staticInterceptorMap.get();
+            constructionHandler = interceptorMap != null ? interceptorMap.get(target) : null;
         } else {
-            interceptor = mocks.get(mock);
+            constructionHandler = interceptorMap.get(target);
         }
-        if (interceptor == null) {
+        if (constructionHandler == null) {
             return null;
         } else {
-            return interceptor.handler;
+            return constructionHandler.handler;
         }
     }
 
-    @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
-        MockMethodInterceptor mockMethodInterceptor =
-                new MockMethodInterceptor(newHandler, settings);
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            if (interceptors == null || !interceptors.containsKey(mock)) {
+    public void resetMockInterceptor(Object target, MockHandler replacementHandler, MockCreationSettings creationSettings) {
+        MockMethodInterceptor methodInterceptor =
+                new MockMethodInterceptor(replacementHandler, creationSettings);
+        if (target instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptorMap = staticInterceptorMap.get();
+            if (interceptorMap == null || !interceptorMap.containsKey(target)) {
                 throw new MockitoException(
                         "Cannot reset "
-                                + mock
+                                + target
                                 + " which is not currently registered as a static mock");
             }
-            interceptors.put((Class<?>) mock, mockMethodInterceptor);
+            interceptorMap.put((Class<?>) target, methodInterceptor);
         } else {
-            if (!mocks.containsKey(mock)) {
+            if (!interceptorMap.containsKey(target)) {
                 throw new MockitoException(
-                        "Cannot reset " + mock + " which is not currently registered as a mock");
+                        "Cannot reset " + target + " which is not currently registered as a mock");
             }
-            mocks.put(mock, mockMethodInterceptor);
-            if (mock instanceof MockAccess) {
-                ((MockAccess) mock).setMockitoInterceptor(mockMethodInterceptor);
+            interceptorMap.put(target, methodInterceptor);
+            if (target instanceof MockAccess) {
+                ((MockAccess) target).setMockitoInterceptor(methodInterceptor);
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
+        classGenerator.clearAllCaches();
     }
 
     @Override
-    public void clearMock(Object mock) {
-        if (mock instanceof Class<?>) {
-            for (Map<Class<?>, ?> entry : mockedStatics.getBackingMap().target.values()) {
-                entry.remove(mock);
+    public void clearMock(Object target) {
+        if (target instanceof Class<?>) {
+            for (Map<Class<?>, ?> typeMap : staticInterceptorMap.getBackingMap().target.values()) {
+                typeMap.remove(target);
             }
         } else {
-            mocks.remove(mock);
+            interceptorMap.remove(target);
         }
     }
 
     @Override
     public void clearAllMocks() {
-        mockedStatics.getBackingMap().clear();
-        mocks.clear();
+        staticInterceptorMap.getBackingMap().clear();
+        interceptorMap.clear();
     }
 
     @Override
-    public TypeMockability isTypeMockable(final Class<?> type) {
+    public TypeMockability isTypeMockable(final Class<?> clazz) {
         return new TypeMockability() {
             @Override
             public boolean mockable() {
-                return INSTRUMENTATION.isModifiableClass(type) && !EXCLUDES.contains(type);
+                return JAVA_AGENT.isModifiableClass(clazz) && !EXCLUDES.contains(clazz);
             }
 
             @Override
@@ -553,10 +549,10 @@ class InlineDelegateByteBuddyMockMaker
                 if (mockable()) {
                     return "";
                 }
-                if (type.isPrimitive()) {
+                if (clazz.isPrimitive()) {
                     return "primitive type";
                 }
-                if (EXCLUDES.contains(type)) {
+                if (EXCLUDES.contains(clazz)) {
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
+        Class<T> clazz, MockCreationSettings<T> creationSettings, MockHandler invocationHandler) {
+        if (clazz == ConcurrentHashMap.class) {
             throw new MockitoException(
                     "It is not possible to mock static methods of ConcurrentHashMap "
                             + "to avoid infinitive loops within Mockito's implementation of static mock handling");
-        } else if (type == Thread.class
-                || type == System.class
-                || type == Arrays.class
-                || ClassLoader.class.isAssignableFrom(type)) {
+        } else if (clazz == Thread.class
+                || clazz == System.class
+                || clazz == Arrays.class
+                || ClassLoader.class.isAssignableFrom(clazz)) {
             throw new MockitoException(
                     "It is not possible to mock static methods of "
-                            + type.getName()
+                            + clazz.getName()
                             + " to avoid interfering with class loading what leads to infinite loops");
         }
 
-        bytecodeGenerator.mockClassStatic(type);
+        classGenerator.mockClassStatic(clazz);
 
-        Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedStatics.set(interceptors);
+        Map<Class<?>, MockMethodInterceptor> interceptorMap = staticInterceptorMap.get();
+        if (interceptorMap == null) {
+            interceptorMap = new WeakHashMap<>();
+            staticInterceptorMap.set(interceptorMap);
         }
-        mockedStatics.getBackingMap().expungeStaleEntries();
+        staticInterceptorMap.getBackingMap().expungeStaleEntries();
 
-        return new InlineStaticMockControl<>(type, interceptors, settings, handler);
+        return new InlineStaticMockManager<>(clazz, interceptorMap, creationSettings, invocationHandler);
     }
 
-    @Override
-    public <T> ConstructionMockControl<T> createConstructionMock(
-            Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
-            Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
-            MockedConstruction.MockInitializer<T> mockInitializer) {
-        if (type == Object.class) {
+    public <T> ConstructionMockControl<T> createMockConstruction(
+            Class<T> clazz,
+            Function<MockedConstruction.Context, MockCreationSettings<T>> creationConfigFactory,
+            Function<MockedConstruction.Context, MockHandler<T>> invocationFactory,
+            MockedConstruction.MockInitializer<T> initCallback) {
+        if (clazz == Object.class) {
             throw new MockitoException(
                     "It is not possible to mock construction of the Object class "
                             + "to avoid inference with default object constructor chains");
-        } else if (type.isPrimitive() || Modifier.isAbstract(type.getModifiers())) {
+        } else if (clazz.isPrimitive() || Modifier.isAbstract(clazz.getModifiers())) {
             throw new MockitoException(
                     "It is not possible to construct primitive types or abstract types: "
-                            + type.getName());
+                            + clazz.getName());
         }
 
-        bytecodeGenerator.mockClassConstruction(type);
+        classGenerator.mockClassConstruction(clazz);
 
-        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
-                mockedConstruction.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedConstruction.set(interceptors);
+        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap =
+                constructionCallbackLocal.get();
+        if (interceptorMap == null) {
+            interceptorMap = new WeakHashMap<>();
+            constructionCallbackLocal.set(interceptorMap);
         }
-        mockedConstruction.getBackingMap().expungeStaleEntries();
+        constructionCallbackLocal.getBackingMap().expungeStaleEntries();
 
-        return new InlineConstructionMockControl<>(
-                type, settingsFactory, handlerFactory, mockInitializer, interceptors);
+        return new InlineMockConstructionController<>(
+            clazz, creationConfigFactory, invocationFactory, initCallback, interceptorMap);
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
+    public <T> T newInstance(Class<T> targetClass) throws InstantiationException {
+        Constructor<?>[] ctors = targetClass.getDeclaredConstructors();
+        if (ctors.length == 0) {
+            throw new InstantiationException(targetClass.getName() + " does not define a constructor");
+        }
+        Constructor<?> chosen = ctors[0];
+        for (Constructor<?> ctor : ctors) {
+            if (Modifier.isPublic(ctor.getModifiers())) {
+                chosen = ctor;
                 break;
             }
         }
-        Class<?>[] types = selected.getParameterTypes();
-        Object[] arguments = new Object[types.length];
-        int index = 0;
-        for (Class<?> type : types) {
-            arguments[index++] = makeStandardArgument(type);
+        Class<?>[] paramClasses = chosen.getParameterTypes();
+        Object[] args = new Object[paramClasses.length];
+        int idx = 0;
+        for (Class<?> clazz : paramClasses) {
+            args[idx++] = makeDefaultArgument(clazz);
         }
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor memberAccess = Plugins.getMemberAccessor();
         try {
             return (T)
-                    accessor.newInstance(
-                            selected,
-                            callback -> {
-                                currentMocking.set(cls);
+                    memberAccess.newInstance(
+                        chosen,
+                        dispatcher -> {
+                                currentTargetClass.set(targetClass);
                                 try {
-                                    return callback.newInstance();
+                                    return dispatcher.newInstance();
                                 } finally {
-                                    currentMocking.remove();
+                                    currentTargetClass.remove();
                                 }
                             },
-                            arguments);
-        } catch (Exception e) {
-            throw new InstantiationException("Could not instantiate " + cls.getName(), e);
+                        args);
+        } catch (Exception instantiationException) {
+            throw new InstantiationException("Could not instantiate " + targetClass.getName(), instantiationException);
         }
     }
 
-    private Object makeStandardArgument(Class<?> type) {
-        if (type == boolean.class) {
+    private Object makeDefaultArgument(Class<?> clazz) {
+        if (clazz == boolean.class) {
             return false;
-        } else if (type == byte.class) {
+        } else if (clazz == byte.class) {
             return (byte) 0;
-        } else if (type == short.class) {
+        } else if (clazz == short.class) {
             return (short) 0;
-        } else if (type == char.class) {
+        } else if (clazz == char.class) {
             return (char) 0;
-        } else if (type == int.class) {
+        } else if (clazz == int.class) {
             return 0;
-        } else if (type == long.class) {
+        } else if (clazz == long.class) {
             return 0L;
-        } else if (type == float.class) {
+        } else if (clazz == float.class) {
             return 0f;
-        } else if (type == double.class) {
+        } else if (clazz == double.class) {
             return 0d;
         } else {
             return null;
         }
     }
 
-    private static class InlineStaticMockControl<T> implements StaticMockControl<T> {
+    private static class InlineStaticMockManager<T> implements StaticMockControl<T> {
 
-        private final Class<T> type;
+        private final Class<T> clazz;
 
-        private final Map<Class<?>, MockMethodInterceptor> interceptors;
+        private final Map<Class<?>, MockMethodInterceptor> interceptorMap;
 
-        private final MockCreationSettings<T> settings;
+        private final MockCreationSettings<T> creationSettings;
 
-        private final MockHandler handler;
+        private final MockHandler invocationHandler;
 
-        private InlineStaticMockControl(
-                Class<T> type,
-                Map<Class<?>, MockMethodInterceptor> interceptors,
-                MockCreationSettings<T> settings,
-                MockHandler handler) {
-            this.type = type;
-            this.interceptors = interceptors;
-            this.settings = settings;
-            this.handler = handler;
+        private InlineStaticMockManager(
+                Class<T> clazz,
+                Map<Class<?>, MockMethodInterceptor> interceptorMap,
+                MockCreationSettings<T> creationSettings,
+                MockHandler invocationHandler) {
+            this.clazz = clazz;
+            this.interceptorMap = interceptorMap;
+            this.creationSettings = creationSettings;
+            this.invocationHandler = invocationHandler;
         }
 
         @Override
         public Class<T> getType() {
-            return type;
+            return clazz;
         }
 
         @Override
         public void enable() {
-            if (interceptors.putIfAbsent(type, new MockMethodInterceptor(handler, settings))
+            if (interceptorMap.putIfAbsent(clazz, new MockMethodInterceptor(invocationHandler, creationSettings))
                     != null) {
                 throw new MockitoException(
                         join(
                                 "For "
-                                        + type.getName()
+                                        + clazz.getName()
                                         + ", static mocking is already registered in the current thread",
                                 "",
                                 "To create a new mock, the existing static mock registration must be deregistered"));
@@ -726,79 +720,79 @@ class InlineDelegateByteBuddyMockMaker
 
         @Override
         public void disable() {
-            if (interceptors.remove(type) == null) {
+            if (interceptorMap.remove(clazz) == null) {
                 throw new MockitoException(
                         join(
                                 "Could not deregister "
-                                        + type.getName()
+                                        + clazz.getName()
                                         + " as a static mock since it is not currently registered",
                                 "",
                                 "To register a static mock, use Mockito.mockStatic("
-                                        + type.getSimpleName()
+                                        + clazz.getSimpleName()
                                         + ".class)"));
             }
         }
     }
 
-    private class InlineConstructionMockControl<T> implements ConstructionMockControl<T> {
+    private class InlineMockConstructionController<T> implements ConstructionMockControl<T> {
 
-        private final Class<T> type;
+        private final Class<T> clazz;
 
-        private final Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory;
-        private final Function<MockedConstruction.Context, MockHandler<T>> handlerFactory;
+        private final Function<MockedConstruction.Context, MockCreationSettings<T>> creationConfigFactory;
+        private final Function<MockedConstruction.Context, MockHandler<T>> invocationFactory;
 
-        private final MockedConstruction.MockInitializer<T> mockInitializer;
+        private final MockedConstruction.MockInitializer<T> initCallback;
 
-        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors;
+        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap;
 
-        private final List<Object> all = new ArrayList<>();
-        private int count;
+        private final List<Object> instances = new ArrayList<>();
+        private int size;
 
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
+        private InlineMockConstructionController(
+                Class<T> clazz,
+                Function<MockedConstruction.Context, MockCreationSettings<T>> creationConfigFactory,
+                Function<MockedConstruction.Context, MockHandler<T>> invocationFactory,
+                MockedConstruction.MockInitializer<T> initCallback,
+                Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap) {
+            this.clazz = clazz;
+            this.creationConfigFactory = creationConfigFactory;
+            this.invocationFactory = invocationFactory;
+            this.initCallback = initCallback;
+            this.interceptorMap = interceptorMap;
         }
 
         @Override
         public Class<T> getType() {
-            return type;
+            return clazz;
         }
 
         @Override
         public void enable() {
-            if (interceptors.putIfAbsent(
-                            type,
-                            (object, context) -> {
-                                ((InlineConstructionMockContext) context).count = ++count;
-                                MockMethodInterceptor interceptor =
+            if (interceptorMap.putIfAbsent(
+                clazz,
+                            (instance, ctx) -> {
+                                ((InlineConstructorMockContext) ctx).size = ++size;
+                                MockMethodInterceptor constructionHandler =
                                         new MockMethodInterceptor(
-                                                handlerFactory.apply(context),
-                                                settingsFactory.apply(context));
-                                mocks.put(object, interceptor);
+                                                invocationFactory.apply(ctx),
+                                                creationConfigFactory.apply(ctx));
+                                InlineDelegateByteBuddyMockFactory.this.interceptorMap.put(instance, constructionHandler);
                                 try {
                                     @SuppressWarnings("unchecked")
-                                    T cast = (T) object;
-                                    mockInitializer.prepare(cast, context);
-                                } catch (Throwable t) {
-                                    mocks.remove(object); // TODO: filter stack trace?
+                                    T typedInstance = (T) instance;
+                                    initCallback.prepare(typedInstance, ctx);
+                                } catch (Throwable throwable) {
+                                    InlineDelegateByteBuddyMockFactory.this.interceptorMap.remove(instance); // TODO: filter stack trace?
                                     throw new MockitoException(
-                                            "Could not initialize mocked construction", t);
+                                            "Could not initialize mocked construction", throwable);
                                 }
-                                all.add(object);
+                                instances.add(instance);
                             })
                     != null) {
                 throw new MockitoException(
                         join(
                                 "For "
-                                        + type.getName()
+                                        + clazz.getName()
                                         + ", static mocking is already registered in the current thread",
                                 "",
                                 "To create a new mock, the existing static mock registration must be deregistered"));
@@ -807,99 +801,99 @@ class InlineDelegateByteBuddyMockMaker
 
         @Override
         public void disable() {
-            if (interceptors.remove(type) == null) {
+            if (interceptorMap.remove(clazz) == null) {
                 throw new MockitoException(
                         join(
                                 "Could not deregister "
-                                        + type.getName()
+                                        + clazz.getName()
                                         + " as a static mock since it is not currently registered",
                                 "",
                                 "To register a static mock, use Mockito.mockStatic("
-                                        + type.getSimpleName()
+                                        + clazz.getSimpleName()
                                         + ".class)"));
             }
-            all.clear();
+            instances.clear();
         }
 
         @Override
         @SuppressWarnings("unchecked")
         public List<T> getMocks() {
-            return (List<T>) all;
+            return (List<T>) instances;
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
+        private int size;
 
-        private final Object[] arguments;
-        private final Class<?> type;
-        private final String[] parameterTypeNames;
+        private final Object[] args;
+        private final Class<?> clazz;
+        private final String[] typeNameArray;
 
-        private InlineConstructionMockContext(
-                Object[] arguments, Class<?> type, String[] parameterTypeNames) {
-            this.arguments = arguments;
-            this.type = type;
-            this.parameterTypeNames = parameterTypeNames;
+        private InlineConstructorMockContext(
+            Object[] args, Class<?> clazz, String[] typeNameArray) {
+            this.args = args;
+            this.clazz = clazz;
+            this.typeNameArray = typeNameArray;
         }
 
         @Override
         public int getCount() {
-            if (count == 0) {
+            if (size == 0) {
                 throw new MockitoConfigurationException(
                         "mocked construction context is not initialized");
             }
-            return count;
+            return size;
         }
 
         @Override
         public Constructor<?> constructor() {
-            Class<?>[] parameterTypes = new Class<?>[parameterTypeNames.length];
-            int index = 0;
-            for (String parameterTypeName : parameterTypeNames) {
-                if (PRIMITIVES.containsKey(parameterTypeName)) {
-                    parameterTypes[index++] = PRIMITIVES.get(parameterTypeName);
+            Class<?>[] paramClasses = new Class<?>[typeNameArray.length];
+            int idx = 0;
+            for (String typeName : typeNameArray) {
+                if (PRIMITIVE_TYPES.containsKey(typeName)) {
+                    paramClasses[idx++] = PRIMITIVE_TYPES.get(typeName);
                 } else {
                     try {
-                        parameterTypes[index++] =
-                                Class.forName(parameterTypeName, false, type.getClassLoader());
-                    } catch (ClassNotFoundException e) {
+                        paramClasses[idx++] =
+                                Class.forName(typeName, false, clazz.getClassLoader());
+                    } catch (ClassNotFoundException instantiationException) {
                         throw new MockitoException(
-                                "Could not find parameter of type " + parameterTypeName, e);
+                                "Could not find parameter of type " + typeName, instantiationException);
                     }
                 }
             }
             try {
-                return type.getDeclaredConstructor(parameterTypes);
-            } catch (NoSuchMethodException e) {
+                return clazz.getDeclaredConstructor(paramClasses);
+            } catch (NoSuchMethodException instantiationException) {
                 throw new MockitoException(
                         join(
                                 "Could not resolve constructor of type",
                                 "",
-                                type.getName(),
+                                clazz.getName(),
                                 "",
                                 "with arguments of types",
-                                Arrays.toString(parameterTypes)),
-                        e);
+                                Arrays.toString(paramClasses)),
+                    instantiationException);
             }
         }
 
         @Override
         public List<?> arguments() {
-            return Collections.unmodifiableList(Arrays.asList(arguments));
+            return Collections.unmodifiableList(Arrays.asList(args));
         }
     }
 }
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
index 9069e50b8..a86d8d80c 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
@@ -14,7 +14,7 @@ import static org.mockito.Mockito.verify;
 
 public class InlineByteBuddyMockMakerTest extends TestBase {
 
-    @Mock private InlineDelegateByteBuddyMockMaker delegate;
+    @Mock private InlineDelegateByteBuddyMockFactory delegate;
 
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
+        verify(delegate).createMockConstruction(Object.class, null, null, null);
         verify(delegate).createMockType(creationSettings);
         verify(delegate).getHandler(this);
         verify(delegate).isTypeMockable(Object.class);
-        verify(delegate).resetMock(this, handler, creationSettings);
+        verify(delegate).resetMockInterceptor(this, handler, creationSettings);
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

