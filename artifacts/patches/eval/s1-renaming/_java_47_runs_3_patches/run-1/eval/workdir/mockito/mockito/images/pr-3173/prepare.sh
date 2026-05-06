#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout bfee15dda7acc41ef497d8f8a44c74dacce2933a

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyInlineDelegateMockMaker.java
similarity index 95%
rename from src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
rename to src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyInlineDelegateMockMaker.java
index 227df4cd1..fb2c4cd5f 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyInlineDelegateMockMaker.java
@@ -100,7 +100,7 @@ import static org.mockito.internal.util.StringUtil.join;
  * support this feature.
  */
 @SuppressSignatureCheck
-class InlineDelegateByteBuddyMockMaker
+class ByteBuddyInlineDelegateMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
 
     private static final Instrumentation INSTRUMENTATION;
@@ -145,7 +145,7 @@ class InlineDelegateByteBuddyMockMaker
                     String source =
                             "org/mockito/internal/creation/bytebuddy/inject/MockMethodDispatcher";
                     InputStream inputStream =
-                            InlineDelegateByteBuddyMockMaker.class
+                            ByteBuddyInlineDelegateMockMaker.class
                                     .getClassLoader()
                                     .getResourceAsStream(source + ".raw");
                     if (inputStream == null) {
@@ -156,7 +156,7 @@ class InlineDelegateByteBuddyMockMaker
                                                 + ".raw",
                                         "",
                                         "The class loader responsible for looking up the resource: "
-                                                + InlineDelegateByteBuddyMockMaker.class
+                                                + ByteBuddyInlineDelegateMockMaker.class
                                                         .getClassLoader()));
                     }
                     outputStream.putNextEntry(new JarEntry(source + ".class"));
@@ -222,7 +222,7 @@ class InlineDelegateByteBuddyMockMaker
 
     private final ThreadLocal<Object> currentSpied = new ThreadLocal<>();
 
-    InlineDelegateByteBuddyMockMaker() {
+    ByteBuddyInlineDelegateMockMaker() {
         if (INITIALIZATION_ERROR != null) {
             String detail;
             if (PlatformUtils.isAndroidPlatform() || PlatformUtils.isProbablyTermuxEnvironment()) {
@@ -324,7 +324,7 @@ class InlineDelegateByteBuddyMockMaker
                             if (interceptor != null) {
                                 interceptor.accept(
                                         object,
-                                        new InlineConstructionMockContext(
+                                        new InlineConstructorMockContext(
                                                 arguments, object.getClass(), parameterTypeNames));
                             }
                         }
@@ -345,26 +345,24 @@ class InlineDelegateByteBuddyMockMaker
                         true);
     }
 
-    @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
-        return doCreateMock(settings, handler, false);
+    public <T> T createMockInstance(MockCreationSettings<T> settings, MockHandler handler) {
+        return createMockInstance(settings, handler, false);
     }
 
-    @Override
-    public <T> Optional<T> createSpy(
+    public <T> Optional<T> createSpyInstance(
             MockCreationSettings<T> settings, MockHandler handler, T object) {
         if (object == null) {
             throw new MockitoConfigurationException("Spy instance must not be null");
         }
         currentSpied.set(object);
         try {
-            return Optional.ofNullable(doCreateMock(settings, handler, true));
+            return Optional.ofNullable(createMockInstance(settings, handler, true));
         } finally {
             currentSpied.remove();
         }
     }
 
-    private <T> T doCreateMock(
+    private <T> T createMockInstance(
             MockCreationSettings<T> settings,
             MockHandler handler,
             boolean nullOnNonInlineConstruction) {
@@ -417,11 +415,11 @@ class InlineDelegateByteBuddyMockMaker
                             settings.isStripAnnotations(),
                             settings.getDefaultAnswer()));
         } catch (Exception bytecodeGenerationFailed) {
-            throw prettifyFailure(settings, bytecodeGenerationFailed);
+            throw prettifyMockingFailure(settings, bytecodeGenerationFailed);
         }
     }
 
-    private <T> RuntimeException prettifyFailure(
+    private <T> RuntimeException prettifyMockingFailure(
             MockCreationSettings<T> mockFeatures, Exception generationFailed) {
         if (mockFeatures.getTypeToMock().isArray()) {
             throw new MockitoException(
@@ -489,8 +487,7 @@ class InlineDelegateByteBuddyMockMaker
         }
     }
 
-    @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+    public void replaceMockInterceptor(Object mock, MockHandler newHandler, MockCreationSettings settings) {
         MockMethodInterceptor mockMethodInterceptor =
                 new MockMethodInterceptor(newHandler, settings);
         if (mock instanceof Class<?>) {
@@ -515,8 +512,7 @@ class InlineDelegateByteBuddyMockMaker
         }
     }
 
-    @Override
-    public void clearAllCaches() {
+    public void clearAllCachesAndMocks() {
         clearAllMocks();
         bytecodeGenerator.clearAllCaches();
     }
@@ -562,8 +558,7 @@ class InlineDelegateByteBuddyMockMaker
         };
     }
 
-    @Override
-    public <T> StaticMockControl<T> createStaticMock(
+    public <T> StaticMockControl<T> createStaticMockController(
             Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
         if (type == ConcurrentHashMap.class) {
             throw new MockitoException(
@@ -588,11 +583,10 @@ class InlineDelegateByteBuddyMockMaker
         }
         mockedStatics.getBackingMap().expungeStaleEntries();
 
-        return new InlineStaticMockControl<>(type, interceptors, settings, handler);
+        return new InlineStaticMockController<>(type, interceptors, settings, handler);
     }
 
-    @Override
-    public <T> ConstructionMockControl<T> createConstructionMock(
+    public <T> ConstructionMockControl<T> createConstructionMockController(
             Class<T> type,
             Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
             Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
@@ -617,7 +611,7 @@ class InlineDelegateByteBuddyMockMaker
         }
         mockedConstruction.getBackingMap().expungeStaleEntries();
 
-        return new InlineConstructionMockControl<>(
+        return new InlineConstructionMockController<>(
                 type, settingsFactory, handlerFactory, mockInitializer, interceptors);
     }
 
@@ -639,7 +633,7 @@ class InlineDelegateByteBuddyMockMaker
         Object[] arguments = new Object[types.length];
         int index = 0;
         for (Class<?> type : types) {
-            arguments[index++] = makeStandardArgument(type);
+            arguments[index++] = createDefaultArgument(type);
         }
         MemberAccessor accessor = Plugins.getMemberAccessor();
         try {
@@ -660,7 +654,7 @@ class InlineDelegateByteBuddyMockMaker
         }
     }
 
-    private Object makeStandardArgument(Class<?> type) {
+    private Object createDefaultArgument(Class<?> type) {
         if (type == boolean.class) {
             return false;
         } else if (type == byte.class) {
@@ -682,7 +676,7 @@ class InlineDelegateByteBuddyMockMaker
         }
     }
 
-    private static class InlineStaticMockControl<T> implements StaticMockControl<T> {
+    private static class InlineStaticMockController<T> implements StaticMockControl<T> {
 
         private final Class<T> type;
 
@@ -692,7 +686,7 @@ class InlineDelegateByteBuddyMockMaker
 
         private final MockHandler handler;
 
-        private InlineStaticMockControl(
+        private InlineStaticMockController(
                 Class<T> type,
                 Map<Class<?>, MockMethodInterceptor> interceptors,
                 MockCreationSettings<T> settings,
@@ -738,7 +732,7 @@ class InlineDelegateByteBuddyMockMaker
         }
     }
 
-    private class InlineConstructionMockControl<T> implements ConstructionMockControl<T> {
+    private class InlineConstructionMockController<T> implements ConstructionMockControl<T> {
 
         private final Class<T> type;
 
@@ -752,7 +746,7 @@ class InlineDelegateByteBuddyMockMaker
         private final List<Object> all = new ArrayList<>();
         private int count;
 
-        private InlineConstructionMockControl(
+        private InlineConstructionMockController(
                 Class<T> type,
                 Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
                 Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
@@ -775,7 +769,7 @@ class InlineDelegateByteBuddyMockMaker
             if (interceptors.putIfAbsent(
                             type,
                             (object, context) -> {
-                                ((InlineConstructionMockContext) context).count = ++count;
+                                ((InlineConstructorMockContext) context).count = ++count;
                                 MockMethodInterceptor interceptor =
                                         new MockMethodInterceptor(
                                                 handlerFactory.apply(context),
@@ -826,7 +820,7 @@ class InlineDelegateByteBuddyMockMaker
         }
     }
 
-    private static class InlineConstructionMockContext implements MockedConstruction.Context {
+    private static class InlineConstructorMockContext implements MockedConstruction.Context {
 
         private static final Map<String, Class<?>> PRIMITIVES = new HashMap<>();
 
@@ -847,7 +841,7 @@ class InlineDelegateByteBuddyMockMaker
         private final Class<?> type;
         private final String[] parameterTypeNames;
 
-        private InlineConstructionMockContext(
+        private InlineConstructorMockContext(
                 Object[] arguments, Class<?> type, String[] parameterTypeNames) {
             this.arguments = arguments;
             this.type = type;
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..be3ed43b3 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -16,18 +16,18 @@ import java.util.function.Function;
 
 public class InlineByteBuddyMockMaker
         implements ClassCreatingMockMaker, InlineMockMaker, Instantiator {
-    private final InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker;
+    private final ByteBuddyInlineDelegateMockMaker inlineDelegateByteBuddyMockMaker;
 
     public InlineByteBuddyMockMaker() {
         try {
-            inlineDelegateByteBuddyMockMaker = new InlineDelegateByteBuddyMockMaker();
+            inlineDelegateByteBuddyMockMaker = new ByteBuddyInlineDelegateMockMaker();
         } catch (NoClassDefFoundError e) {
             Reporter.missingByteBuddyDependency(e);
             throw e;
         }
     }
 
-    InlineByteBuddyMockMaker(InlineDelegateByteBuddyMockMaker inlineDelegateByteBuddyMockMaker) {
+    InlineByteBuddyMockMaker(ByteBuddyInlineDelegateMockMaker inlineDelegateByteBuddyMockMaker) {
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
+        inlineDelegateByteBuddyMockMaker.replaceMockInterceptor(mock, newHandler, settings);
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
+        inlineDelegateByteBuddyMockMaker.clearAllCachesAndMocks();
     }
 }
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
index 9069e50b8..b15d01371 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
@@ -14,7 +14,7 @@ import static org.mockito.Mockito.verify;
 
 public class InlineByteBuddyMockMakerTest extends TestBase {
 
-    @Mock private InlineDelegateByteBuddyMockMaker delegate;
+    @Mock private ByteBuddyInlineDelegateMockMaker delegate;
 
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
+        verify(delegate).replaceMockInterceptor(this, handler, creationSettings);
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

