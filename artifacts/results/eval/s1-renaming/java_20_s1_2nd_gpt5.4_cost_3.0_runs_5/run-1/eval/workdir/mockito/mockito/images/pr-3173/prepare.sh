#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout bfee15dda7acc41ef497d8f8a44c74dacce2933a

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..f5f227303 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -16,18 +16,18 @@ import java.util.function.Function;
 
 public class InlineByteBuddyMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
-    private final InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
+    private final InlineDelegatingByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
 
     public InlineByteBuddyMockMaker() {
         try {
-            inlineDelegateByteBuddyMockMaker = new InlineDelegateByteBuddyMockMaker();
+            inlineDelegateByteBuddyMockMaker = new InlineDelegatingByteBuddyMockMaker();
         } catch (NoClassDefFoundError e) {
             Reporter.missingByteBuddyDependency(e);
             throw e;
         }
     }
 
-    InlineByteBuddyMockMaker(InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
+    InlineByteBuddyMockMaker(InlineDelegatingByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
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
+        return inlineDelegateByteBuddyMockMaker.makeSpy(settings, handler, instance);
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
+        inlineDelegateByteBuddyMockMaker.clearCaches();
     }
 }
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegatingByteBuddyMockMaker.java
similarity index 57%
rename from src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
rename to src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegatingByteBuddyMockMaker.java
index 227df4cd1..7d8972cb0 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegatingByteBuddyMockMaker.java
@@ -100,12 +100,12 @@ import static org.mockito.internal.util.StringUtil.join;
  * support this feature.
  */
 @SuppressSignatureCheck
-class InlineDelegateByteBuddyMockMaker
+class InlineDelegatingByteBuddyMockMaker
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
+                            InlineDelegatingByteBuddyMockMaker.class
                                     .getClassLoader()
                                     .getResourceAsStream(source + ".raw");
                     if (inputStream == null) {
@@ -156,7 +156,7 @@ class InlineDelegateByteBuddyMockMaker
                                                 + ".raw",
                                         "",
                                         "The class loader responsible for looking up the resource: "
-                                                + InlineDelegateByteBuddyMockMaker.class
+                                                + InlineDelegatingByteBuddyMockMaker.class
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
+    private final BytecodeGenerator codeGenerator;
 
-    private final WeakConcurrentMap<Object, MockMethodInterceptor> mocks =
+    private final WeakConcurrentMap<Object, MockMethodInterceptor> interceptorRegistry =
             new WeakConcurrentMap<>(false);
 
-    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> mockedStatics =
+    private final DetachedThreadLocal<Map<Class<?>, MockMethodInterceptor>> staticInterceptorLocal =
             new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
     private final DetachedThreadLocal<Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>>>
-            mockedConstruction = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
+        constructionInterceptorLocal = new DetachedThreadLocal<>(DetachedThreadLocal.Cleaner.MANUAL);
 
-    private final ThreadLocal<Boolean> mockitoConstruction = ThreadLocal.withInitial(() -> false);
+    private final ThreadLocal<Boolean> inlineConstructionFlag = ThreadLocal.withInitial(() -> false);
 
-    private final ThreadLocal<Object> currentSpied = new ThreadLocal<>();
+    private final ThreadLocal<Object> currentSpy = new ThreadLocal<>();
 
-    InlineDelegateByteBuddyMockMaker() {
-        if (INITIALIZATION_ERROR != null) {
-            String detail;
+    InlineDelegatingByteBuddyMockMaker() {
+        if (INIT_FAILURE != null) {
+            String messageInfo;
             if (PlatformUtils.isAndroidPlatform() || PlatformUtils.isProbablyTermuxEnvironment()) {
-                detail =
+                messageInfo =
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
+                        messageInfo =
                                 join(
                                         "It seems like you are running Mockito with an incomplete or inconsistent class path. Byte Buddy Agent could not be loaded.",
                                         "",
@@ -245,14 +245,14 @@ class InlineDelegateByteBuddyMockMaker
                                     .getMethod("getSystemJavaCompiler")
                                     .invoke(null)
                             == null) {
-                        detail =
+                        messageInfo =
                                 "It appears as if you are running on a JRE. Either install a JDK or add JNA to the class path.";
                     } else {
-                        detail =
+                        messageInfo =
                                 "It appears as if your JDK does not supply a working agent attachment mechanism.";
                     }
-                } catch (Throwable ignored) {
-                    detail =
+                } catch (Throwable suppressedCause) {
+                    messageInfo =
                             "It appears as if you are running an incomplete JVM installation that might not support all tooling APIs";
                 }
             }
@@ -260,178 +260,176 @@ class InlineDelegateByteBuddyMockMaker
                     join(
                             "Could not initialize inline Byte Buddy mock maker.",
                             "",
-                            detail,
+                        messageInfo,
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
+        ThreadLocal<Boolean> suspendedFlagLocal = ThreadLocal.withInitial(() -> false);
+        Predicate<Class<?>> subclassConstructorPredicate = StackWalkerChecker.orFallback();
+        Predicate<Class<?>> constructionMockPredicate =
+            clazz -> {
+                    if (suspendedFlagLocal.get()) {
                         return false;
-                    } else if (mockitoConstruction.get() || currentConstruction.get() != null) {
+                    } else if (inlineConstructionFlag.get() || constructionTypeLocal.get() != null) {
                         return true;
                     }
-                    Map<Class<?>, ?> interceptors = mockedConstruction.get();
-                    if (interceptors != null && interceptors.containsKey(type)) {
+                    Map<Class<?>, ?> interceptorMap = constructionInterceptorLocal.get();
+                    if (interceptorMap != null && interceptorMap.containsKey(clazz)) {
                         // We only initiate a construction mock, if the call originates from an
                         // un-mocked (as suppression is not enabled) subclass constructor.
-                        if (isCallFromSubclassConstructor.test(type)) {
+                        if (subclassConstructorPredicate.test(clazz)) {
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
-                    if (mockitoConstruction.get()) {
-                        Object spy = currentSpied.get();
-                        if (spy == null) {
+        ConstructionCallback constructionCallback =
+                (clazz, candidate, methodArgs, paramTypeNames) -> {
+                    if (inlineConstructionFlag.get()) {
+                        Object spyInstance = currentSpy.get();
+                        if (spyInstance == null) {
                             return null;
-                        } else if (type.isInstance(spy)) {
-                            return spy;
+                        } else if (clazz.isInstance(spyInstance)) {
+                            return spyInstance;
                         } else {
-                            isSuspended.set(true);
+                            suspendedFlagLocal.set(true);
                             try {
                                 // Unexpected construction of non-spied object
                                 throw new MockitoException(
                                         "Unexpected spy for "
-                                                + type.getName()
+                                                + clazz.getName()
                                                 + " on instance of "
-                                                + object.getClass().getName(),
-                                        object instanceof Throwable ? (Throwable) object : null);
+                                                + candidate.getClass().getName(),
+                                        candidate instanceof Throwable ? (Throwable) candidate : null);
                             } finally {
-                                isSuspended.set(false);
+                                suspendedFlagLocal.set(false);
                             }
                         }
-                    } else if (currentConstruction.get() != type) {
+                    } else if (constructionTypeLocal.get() != clazz) {
                         return null;
                     }
-                    currentConstruction.remove();
-                    isSuspended.set(true);
+                    constructionTypeLocal.remove();
+                    suspendedFlagLocal.set(true);
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
+                                constructionInterceptorLocal.get();
+                        if (interceptorMap != null) {
+                            BiConsumer<Object, MockedConstruction.Context> handlerConsumer =
+                                    interceptorMap.get(clazz);
+                            if (handlerConsumer != null) {
+                                handlerConsumer.accept(
+                                    candidate,
+                                        new InlineConstructorMockContext(
+                                            methodArgs, candidate.getClass(), paramTypeNames));
                             }
                         }
                     } finally {
-                        isSuspended.set(false);
+                        suspendedFlagLocal.set(false);
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
+                            interceptorRegistry,
+                            staticInterceptorLocal,
+                            constructionMockPredicate,
+                            constructionCallback),
                         true);
     }
 
-    @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return doCreateMock(settings, handler, false);
+    public <T> T createMockInstance(MockCreationSettings<T> creationSettings, MockHandler mockOperator) {
+        return createMockInstance(creationSettings, mockOperator, false);
     }
 
-    @Override
-    public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T object) {
-        if (object == null) {
+    public <T> Optional<T> makeSpy(
+        MockCreationSettings<T> creationSettings, MockHandler mockOperator, T candidate) {
+        if (candidate == null) {
             throw new MockitoConfigurationException("Spy instance must not be null");
         }
-        currentSpied.set(object);
+        currentSpy.set(candidate);
         try {
-            return Optional.ofNullable(doCreateMock(settings, handler, true));
+            return Optional.ofNullable(createMockInstance(creationSettings, mockOperator, true));
         } finally {
-            currentSpied.remove();
+            currentSpy.remove();
         }
     }
 
-    private <T> T doCreateMock(
-            MockCreationSettings<T> settings,
-            MockHandler handler,
-            boolean nullOnNonInlineConstruction) {
-        Class<? extends T> type = createMockType(settings);
+    private <T> T createMockInstance(
+            MockCreationSettings<T> creationSettings,
+            MockHandler mockOperator,
+            boolean nullWhenNonInline) {
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
+                } catch (InstantiationException suppressedCause) {
+                    if (nullWhenNonInline) {
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
+                    new MockMethodInterceptor(mockOperator, creationSettings);
+            interceptorRegistry.put(createdInstance, methodInterceptor);
+            if (createdInstance instanceof MockAccess) {
+                ((MockAccess) createdInstance).setMockitoInterceptor(methodInterceptor);
             }
-            mocks.expungeStaleEntries();
-            return instance;
-        } catch (InstantiationException e) {
+            interceptorRegistry.expungeStaleEntries();
+            return createdInstance;
+        } catch (InstantiationException ex) {
             throw new MockitoException(
-                    "Unable to create mock instance of type '" + type.getSimpleName() + "'", e);
+                    "Unable to create mock instance of type '" + clazz.getSimpleName() + "'", ex);
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
+            throw formatMockingFailure(creationSettings, generationException);
         }
     }
 
-    private <T> RuntimeException prettifyFailure(
-            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
-        if (mockFeatures.getTypeToMock().isArray()) {
+    private <T> RuntimeException formatMockingFailure(
+        MockCreationSettings<T> creationSettings, Exception cause) {
+        if (creationSettings.getTypeToMock().isArray()) {
             throw new MockitoException(
-                    join("Arrays cannot be mocked: " + mockFeatures.getTypeToMock() + ".", ""),
-                    generationFailed);
+                    join("Arrays cannot be mocked: " + creationSettings.getTypeToMock() + ".", ""),
+                cause);
         }
-        if (Modifier.isFinal(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isFinal(creationSettings.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + creationSettings.getTypeToMock() + ".",
                             "Can not mock final classes with the following settings :",
                             " - explicit serialization (e.g. withSettings().serializable())",
                             " - extra interfaces (e.g. withSettings().extraInterfaces(...))",
@@ -439,23 +437,23 @@ class InlineDelegateByteBuddyMockMaker
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             "",
-                            "Underlying exception : " + generationFailed),
-                    generationFailed);
+                            "Underlying exception : " + cause),
+                cause);
         }
-        if (Modifier.isPrivate(mockFeatures.getTypeToMock().getModifiers())) {
+        if (Modifier.isPrivate(creationSettings.getTypeToMock().getModifiers())) {
             throw new MockitoException(
                     join(
-                            "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                            "Mockito cannot mock this class: " + creationSettings.getTypeToMock() + ".",
                             "Most likely it is a private class that is not visible by Mockito",
                             "",
                             "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                             "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                             ""),
-                    generationFailed);
+                cause);
         }
         throw new MockitoException(
                 join(
-                        "Mockito cannot mock this class: " + mockFeatures.getTypeToMock() + ".",
+                        "Mockito cannot mock this class: " + creationSettings.getTypeToMock() + ".",
                         "",
                         "If you're not sure why you're getting this error, please open an issue on GitHub.",
                         "",
@@ -469,81 +467,79 @@ class InlineDelegateByteBuddyMockMaker
                         "You are seeing this disclaimer because Mockito is configured to create inlined mocks.",
                         "You can learn about inline mocks and their limitations under item #39 of the Mockito class javadoc.",
                         "",
-                        "Underlying exception : " + generationFailed),
-                generationFailed);
+                        "Underlying exception : " + cause),
+            cause);
     }
 
     @Override
-    public MockHandler getHandler(Object mock) {
-        MockMethodInterceptor interceptor;
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            interceptor = interceptors != null ? interceptors.get(mock) : null;
+    public MockHandler getHandler(Object candidate) {
+        MockMethodInterceptor handlerConsumer;
+        if (candidate instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptorMap = staticInterceptorLocal.get();
+            handlerConsumer = interceptorMap != null ? interceptorMap.get(candidate) : null;
         } else {
-            interceptor = mocks.get(mock);
+            handlerConsumer = interceptorRegistry.get(candidate);
         }
-        if (interceptor == null) {
+        if (handlerConsumer == null) {
             return null;
         } else {
-            return interceptor.handler;
+            return handlerConsumer.handler;
         }
     }
 
-    @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
-        MockMethodInterceptor mockMethodInterceptor =
-                new MockMethodInterceptor(newHandler, settings);
-        if (mock instanceof Class<?>) {
-            Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-            if (interceptors == null || !interceptors.containsKey(mock)) {
+    public void resetMockInterceptor(Object candidate, MockHandler replacement, MockCreationSettings creationSettings) {
+        MockMethodInterceptor methodInterceptor =
+                new MockMethodInterceptor(replacement, creationSettings);
+        if (candidate instanceof Class<?>) {
+            Map<Class<?>, MockMethodInterceptor> interceptorMap = staticInterceptorLocal.get();
+            if (interceptorMap == null || !interceptorMap.containsKey(candidate)) {
                 throw new MockitoException(
                         "Cannot reset "
-                                + mock
+                                + candidate
                                 + " which is not currently registered as a static mock");
             }
-            interceptors.put((Class<?>) mock, mockMethodInterceptor);
+            interceptorMap.put((Class<?>) candidate, methodInterceptor);
         } else {
-            if (!mocks.containsKey(mock)) {
+            if (!interceptorRegistry.containsKey(candidate)) {
                 throw new MockitoException(
-                        "Cannot reset " + mock + " which is not currently registered as a mock");
+                        "Cannot reset " + candidate + " which is not currently registered as a mock");
             }
-            mocks.put(mock, mockMethodInterceptor);
-            if (mock instanceof MockAccess) {
-                ((MockAccess) mock).setMockitoInterceptor(mockMethodInterceptor);
+            interceptorRegistry.put(candidate, methodInterceptor);
+            if (candidate instanceof MockAccess) {
+                ((MockAccess) candidate).setMockitoInterceptor(methodInterceptor);
             }
-            mocks.expungeStaleEntries();
+            interceptorRegistry.expungeStaleEntries();
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
+            for (Map<Class<?>, ?> classMap : staticInterceptorLocal.getBackingMap().target.values()) {
+                classMap.remove(candidate);
             }
         } else {
-            mocks.remove(mock);
+            interceptorRegistry.remove(candidate);
         }
     }
 
     @Override
     public void clearAllMocks() {
-        mockedStatics.getBackingMap().clear();
-        mocks.clear();
+        staticInterceptorLocal.getBackingMap().clear();
+        interceptorRegistry.clear();
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
@@ -551,10 +547,10 @@ class InlineDelegateByteBuddyMockMaker
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
@@ -562,160 +558,158 @@ class InlineDelegateByteBuddyMockMaker
         };
     }
 
-    @Override
-    public <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
-        if (type == ConcurrentHashMap.class) {
+    public <T> StaticMockControl<T> createStaticMockController(
+        Class<T> clazz, MockCreationSettings<T> creationSettings, MockHandler mockOperator) {
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
+        codeGenerator.mockClassStatic(clazz);
 
-        Map<Class<?>, MockMethodInterceptor> interceptors = mockedStatics.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedStatics.set(interceptors);
+        Map<Class<?>, MockMethodInterceptor> interceptorMap = staticInterceptorLocal.get();
+        if (interceptorMap == null) {
+            interceptorMap = new WeakHashMap<>();
+            staticInterceptorLocal.set(interceptorMap);
         }
-        mockedStatics.getBackingMap().expungeStaleEntries();
+        staticInterceptorLocal.getBackingMap().expungeStaleEntries();
 
-        return new InlineStaticMockControl<>(type, interceptors, settings, handler);
+        return new InlineStaticMockController<>(clazz, interceptorMap, creationSettings, mockOperator);
     }
 
-    @Override
-    public <T> ConstructionMockControl<T> createConstructionMock(
-            Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
-            Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
-            MockedConstruction.MockInitializer<T> mockInitializer) {
-        if (type == Object.class) {
+    public <T> ConstructionMockControl<T> createConstructionMockController(
+            Class<T> clazz,
+            Function<MockedConstruction.Context, MockCreationSettings<T>> creationConfigProvider,
+            Function<MockedConstruction.Context, MockHandler<T>> invocationFactory,
+            MockedConstruction.MockInitializer<T> instanceConfigurer) {
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
+        codeGenerator.mockClassConstruction(clazz);
 
-        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors =
-                mockedConstruction.get();
-        if (interceptors == null) {
-            interceptors = new WeakHashMap<>();
-            mockedConstruction.set(interceptors);
+        Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap =
+                constructionInterceptorLocal.get();
+        if (interceptorMap == null) {
+            interceptorMap = new WeakHashMap<>();
+            constructionInterceptorLocal.set(interceptorMap);
         }
-        mockedConstruction.getBackingMap().expungeStaleEntries();
+        constructionInterceptorLocal.getBackingMap().expungeStaleEntries();
 
-        return new InlineConstructionMockControl<>(
-                type, settingsFactory, handlerFactory, mockInitializer, interceptors);
+        return new InlineConstructionMockController<>(
+            clazz, creationConfigProvider, invocationFactory, instanceConfigurer, interceptorMap);
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
+        Constructor<?>[] ctorCandidates = targetClass.getDeclaredConstructors();
+        if (ctorCandidates.length == 0) {
+            throw new InstantiationException(targetClass.getName() + " does not define a constructor");
+        }
+        Constructor<?> chosenCtor = ctorCandidates[0];
+        for (Constructor<?> ctorParam : ctorCandidates) {
+            if (Modifier.isPublic(ctorParam.getModifiers())) {
+                chosenCtor = ctorParam;
                 break;
             }
         }
-        Class<?>[] types = selected.getParameterTypes();
-        Object[] arguments = new Object[types.length];
-        int index = 0;
-        for (Class<?> type : types) {
-            arguments[index++] = makeStandardArgument(type);
+        Class<?>[] paramClasses = chosenCtor.getParameterTypes();
+        Object[] methodArgs = new Object[paramClasses.length];
+        int pos = 0;
+        for (Class<?> clazz : paramClasses) {
+            methodArgs[pos++] = createDefaultArgument(clazz);
         }
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor accessHelper = Plugins.getMemberAccessor();
         try {
             return (T)
-                    accessor.newInstance(
-                            selected,
-                            callback -> {
-                                mockitoConstruction.set(true);
+                    accessHelper.newInstance(
+                        chosenCtor,
+                        constructionDispatcher -> {
+                                inlineConstructionFlag.set(true);
                                 try {
-                                    return callback.newInstance();
+                                    return constructionDispatcher.newInstance();
                                 } finally {
-                                    mockitoConstruction.set(false);
+                                    inlineConstructionFlag.set(false);
                                 }
                             },
-                            arguments);
-        } catch (Exception e) {
-            throw new InstantiationException("Could not instantiate " + cls.getName(), e);
+                        methodArgs);
+        } catch (Exception ex) {
+            throw new InstantiationException("Could not instantiate " + targetClass.getName(), ex);
         }
     }
 
-    private Object makeStandardArgument(Class<?> type) {
-        if (type == boolean.class) {
+    private Object createDefaultArgument(Class<?> clazz) {
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
+    private static class InlineStaticMockController<T> implements StaticMockControl<T> {
 
-        private final Class<T> type;
+        private final Class<T> clazz;
 
-        private final Map<Class<?>, MockMethodInterceptor> interceptors;
+        private final Map<Class<?>, MockMethodInterceptor> interceptorMap;
 
-        private final MockCreationSettings<T> settings;
+        private final MockCreationSettings<T> creationSettings;
 
-        private final MockHandler handler;
+        private final MockHandler mockOperator;
 
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
+                Class<T> clazz,
+                Map<Class<?>, MockMethodInterceptor> interceptorMap,
+                MockCreationSettings<T> creationSettings,
+                MockHandler mockOperator) {
+            this.clazz = clazz;
+            this.interceptorMap = interceptorMap;
+            this.creationSettings = creationSettings;
+            this.mockOperator = mockOperator;
         }
 
         @Override
         public Class<T> getType() {
-            return type;
+            return clazz;
         }
 
         @Override
         public void enable() {
-            if (interceptors.putIfAbsent(type, new MockMethodInterceptor(handler, settings))
+            if (interceptorMap.putIfAbsent(clazz, new MockMethodInterceptor(mockOperator, creationSettings))
                     != null) {
                 throw new MockitoException(
                         join(
                                 "For "
-                                        + type.getName()
+                                        + clazz.getName()
                                         + ", static mocking is already registered in the current thread",
                                 "",
                                 "To create a new mock, the existing static mock registration must be deregistered"));
@@ -724,79 +718,79 @@ class InlineDelegateByteBuddyMockMaker
 
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
+    private class InlineConstructionMockController<T> implements ConstructionMockControl<T> {
 
-        private final Class<T> type;
+        private final Class<T> clazz;
 
-        private final Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory;
-        private final Function<MockedConstruction.Context, MockHandler<T>> handlerFactory;
+        private final Function<MockedConstruction.Context, MockCreationSettings<T>> creationConfigProvider;
+        private final Function<MockedConstruction.Context, MockHandler<T>> invocationFactory;
 
-        private final MockedConstruction.MockInitializer<T> mockInitializer;
+        private final MockedConstruction.MockInitializer<T> instanceConfigurer;
 
-        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors;
+        private final Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap;
 
-        private final List<Object> all = new ArrayList<>();
-        private int count;
+        private final List<Object> instances = new ArrayList<>();
+        private int totalInstances;
 
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
+                Class<T> clazz,
+                Function<MockedConstruction.Context, MockCreationSettings<T>> creationConfigProvider,
+                Function<MockedConstruction.Context, MockHandler<T>> invocationFactory,
+                MockedConstruction.MockInitializer<T> instanceConfigurer,
+                Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptorMap) {
+            this.clazz = clazz;
+            this.creationConfigProvider = creationConfigProvider;
+            this.invocationFactory = invocationFactory;
+            this.instanceConfigurer = instanceConfigurer;
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
+                            (candidate, ctx) -> {
+                                ((InlineConstructorMockContext) ctx).totalInstances = ++totalInstances;
+                                MockMethodInterceptor handlerConsumer =
                                         new MockMethodInterceptor(
-                                                handlerFactory.apply(context),
-                                                settingsFactory.apply(context));
-                                mocks.put(object, interceptor);
+                                                invocationFactory.apply(ctx),
+                                                creationConfigProvider.apply(ctx));
+                                interceptorRegistry.put(candidate, handlerConsumer);
                                 try {
                                     @SuppressWarnings("unchecked")
-                                    T cast = (T) object;
-                                    mockInitializer.prepare(cast, context);
-                                } catch (Throwable t) {
-                                    mocks.remove(object); // TODO: filter stack trace?
+                                    T castedInstance = (T) candidate;
+                                    instanceConfigurer.prepare(castedInstance, ctx);
+                                } catch (Throwable throwable) {
+                                    interceptorRegistry.remove(candidate); // TODO: filter stack trace?
                                     throw new MockitoException(
-                                            "Could not initialize mocked construction", t);
+                                            "Could not initialize mocked construction", throwable);
                                 }
-                                all.add(object);
+                                instances.add(candidate);
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
@@ -805,99 +799,99 @@ class InlineDelegateByteBuddyMockMaker
 
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
+        private int totalInstances;
 
-        private final Object[] arguments;
-        private final Class<?> type;
-        private final String[] parameterTypeNames;
+        private final Object[] methodArgs;
+        private final Class<?> clazz;
+        private final String[] paramTypeNames;
 
-        private InlineConstructionMockContext(
-                Object[] arguments, Class<?> type, String[] parameterTypeNames) {
-            this.arguments = arguments;
-            this.type = type;
-            this.parameterTypeNames = parameterTypeNames;
+        private InlineConstructorMockContext(
+            Object[] methodArgs, Class<?> clazz, String[] paramTypeNames) {
+            this.methodArgs = methodArgs;
+            this.clazz = clazz;
+            this.paramTypeNames = paramTypeNames;
         }
 
         @Override
         public int getCount() {
-            if (count == 0) {
+            if (totalInstances == 0) {
                 throw new MockitoConfigurationException(
                         "mocked construction context is not initialized");
             }
-            return count;
+            return totalInstances;
         }
 
         @Override
         public Constructor<?> constructor() {
-            Class<?>[] parameterTypes = new Class<?>[parameterTypeNames.length];
-            int index = 0;
-            for (String parameterTypeName : parameterTypeNames) {
-                if (PRIMITIVES.containsKey(parameterTypeName)) {
-                    parameterTypes[index++] = PRIMITIVES.get(parameterTypeName);
+            Class<?>[] parameterClasses = new Class<?>[paramTypeNames.length];
+            int pos = 0;
+            for (String parameterClassName : paramTypeNames) {
+                if (PRIMITIVE_TYPES.containsKey(parameterClassName)) {
+                    parameterClasses[pos++] = PRIMITIVE_TYPES.get(parameterClassName);
                 } else {
                     try {
-                        parameterTypes[index++] =
-                                Class.forName(parameterTypeName, false, type.getClassLoader());
-                    } catch (ClassNotFoundException e) {
+                        parameterClasses[pos++] =
+                                Class.forName(parameterClassName, false, clazz.getClassLoader());
+                    } catch (ClassNotFoundException ex) {
                         throw new MockitoException(
-                                "Could not find parameter of type " + parameterTypeName, e);
+                                "Could not find parameter of type " + parameterClassName, ex);
                     }
                 }
             }
             try {
-                return type.getDeclaredConstructor(parameterTypes);
-            } catch (NoSuchMethodException e) {
+                return clazz.getDeclaredConstructor(parameterClasses);
+            } catch (NoSuchMethodException ex) {
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
+                                Arrays.toString(parameterClasses)),
+                    ex);
             }
         }
 
         @Override
         public List<?> arguments() {
-            return Collections.unmodifiableList(Arrays.asList(arguments));
+            return Collections.unmodifiableList(Arrays.asList(methodArgs));
         }
     }
 }
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
index 9069e50b8..ba4f5059d 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
@@ -14,7 +14,7 @@ import static org.mockito.Mockito.verify;
 
 public class InlineByteBuddyMockMakerTest extends TestBase {
 
-    @Mock private InlineDelegateByteBuddyMockMaker delegate;
+    @Mock private InlineDelegatingByteBuddyMockMaker delegate;
 
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
+        verify(delegate).clearCaches();
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

