#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout edc624371009ce981bbc11b7d125ff4e359cff7e

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/ArgumentCaptor.java b/src/main/java/org/mockito/ArgumentCaptor.java
index 2fdeb628d..1f788e44b 100644
--- a/src/main/java/org/mockito/ArgumentCaptor.java
+++ b/src/main/java/org/mockito/ArgumentCaptor.java
@@ -52,11 +52,11 @@ import org.mockito.internal.matchers.CapturingMatcher;
  * <p>
  * This utility class <strong>will</strong> perform type checking on the generic type (since Mockito 5.0.0).
  * <p>
- * There is an <strong>annotation</strong> that you might find useful: &#64;{@link Captor}
+ * There is an <strong>annotation</strong> that you might find useful: &#64;{@link Capturer}
  * <p>
  * See the full documentation on Mockito in javadoc for {@link Mockito} class.
  *
- * @see Captor
+ * @see Capturer
  * @since 1.8.0
  */
 @CheckReturnValue
diff --git a/src/main/java/org/mockito/Captor.java b/src/main/java/org/mockito/Capturer.java
similarity index 97%
rename from src/main/java/org/mockito/Captor.java
rename to src/main/java/org/mockito/Capturer.java
index 0de9f72b2..4ee3089b0 100644
--- a/src/main/java/org/mockito/Captor.java
+++ b/src/main/java/org/mockito/Capturer.java
@@ -48,4 +48,4 @@ import java.lang.annotation.Target;
 @Retention(RetentionPolicy.RUNTIME)
 @Target(ElementType.FIELD)
 @Documented
-public @interface Captor {}
+public @interface Capturer {}
diff --git a/src/main/java/org/mockito/Mockito.java b/src/main/java/org/mockito/Mockito.java
index ee5a13303..06c7f7faa 100644
--- a/src/main/java/org/mockito/Mockito.java
+++ b/src/main/java/org/mockito/Mockito.java
@@ -861,7 +861,7 @@ import java.util.function.Function;
  * Release 1.8.3 brings new annotations that may be helpful on occasion:
  *
  * <ul>
- * <li>&#064;{@link Captor} simplifies creation of {@link ArgumentCaptor}
+ * <li>&#064;{@link Capturer} simplifies creation of {@link ArgumentCaptor}
  * - useful when the argument to capture is a nasty generic class and you want to avoid compiler warnings
  * <li>&#064;{@link Spy} - you can use it instead {@link Mockito#spy(Object)}.
  * <li>&#064;{@link InjectMocks} - injects mock or spy fields into tested object automatically.
diff --git a/src/main/java/org/mockito/MockitoAnnotations.java b/src/main/java/org/mockito/MockitoAnnotations.java
index 5857478ca..cf682fb3f 100644
--- a/src/main/java/org/mockito/MockitoAnnotations.java
+++ b/src/main/java/org/mockito/MockitoAnnotations.java
@@ -51,7 +51,7 @@ import org.mockito.plugins.AnnotationEngine;
  *   }
  * </code></pre>
  * <p>
- * Read also about other annotations &#064;{@link Spy}, &#064;{@link Captor}, &#064;{@link InjectMocks}
+ * Read also about other annotations &#064;{@link Spy}, &#064;{@link Capturer}, &#064;{@link InjectMocks}
  * <p>
  * <b><code>MockitoAnnotations.openMocks(this)</code></b> method has to be called to initialize annotated fields.
  * <p>
@@ -64,7 +64,7 @@ public final class MockitoAnnotations {
 
     /**
      * Initializes objects annotated with Mockito annotations for given testClass:
-     *  &#064;{@link org.mockito.Mock}, &#064;{@link Spy}, &#064;{@link Captor}, &#064;{@link InjectMocks}
+     *  &#064;{@link org.mockito.Mock}, &#064;{@link Spy}, &#064;{@link Capturer}, &#064;{@link InjectMocks}
      * <p>
      * See examples in javadoc for {@link MockitoAnnotations} class.
      *
@@ -83,7 +83,7 @@ public final class MockitoAnnotations {
 
     /**
      * Initializes objects annotated with Mockito annotations for given testClass:
-     *  &#064;{@link org.mockito.Mock}, &#064;{@link Spy}, &#064;{@link Captor}, &#064;{@link InjectMocks}
+     *  &#064;{@link org.mockito.Mock}, &#064;{@link Spy}, &#064;{@link Capturer}, &#064;{@link InjectMocks}
      * <p>
      * See examples in javadoc for {@link MockitoAnnotations} class.
      *
diff --git a/src/main/java/org/mockito/internal/configuration/CaptorAnnotationProcessor.java b/src/main/java/org/mockito/internal/configuration/CaptorProcessor.java
similarity index 58%
rename from src/main/java/org/mockito/internal/configuration/CaptorAnnotationProcessor.java
rename to src/main/java/org/mockito/internal/configuration/CaptorProcessor.java
index 600583be5..67e085316 100644
--- a/src/main/java/org/mockito/internal/configuration/CaptorAnnotationProcessor.java
+++ b/src/main/java/org/mockito/internal/configuration/CaptorProcessor.java
@@ -7,26 +7,26 @@ package org.mockito.internal.configuration;
 import java.lang.reflect.Field;
 
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.util.reflection.GenericMaster;
+import org.mockito.internal.util.reflection.GenericTypeManager;
 
 /**
  * Instantiate {@link ArgumentCaptor} a field annotated by &#64;Captor.
  */
-public class CaptorAnnotationProcessor implements FieldAnnotationProcessor<Captor> {
+public class CaptorProcessor implements FieldAnnotationProcessor<Capturer> {
     @Override
-    public Object process(Captor annotation, Field field) {
-        Class<?> type = field.getType();
-        if (!ArgumentCaptor.class.isAssignableFrom(type)) {
+    public Object process(Capturer capturer, Field member) {
+        Class<?> targetClass = member.getType();
+        if (!ArgumentCaptor.class.isAssignableFrom(targetClass)) {
             throw new MockitoException(
                     "@Captor field must be of the type ArgumentCaptor.\n"
                             + "Field: '"
-                            + field.getName()
+                            + member.getName()
                             + "' has wrong type\n"
                             + "For info how to use @Captor annotations see examples in javadoc for MockitoAnnotations class.");
         }
-        Class<?> cls = new GenericMaster().getGenericType(field);
-        return ArgumentCaptor.forClass(cls);
+        Class<?> runtimeClass = new GenericTypeManager().getGenericType(member);
+        return ArgumentCaptor.forClass(runtimeClass);
     }
 }
diff --git a/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java b/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
index a7950da9f..6882a99ec 100644
--- a/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
+++ b/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
@@ -13,7 +13,7 @@ import java.util.HashMap;
 import java.util.List;
 import java.util.Map;
 
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.Mock;
 import org.mockito.MockitoAnnotations;
 import org.mockito.ScopedMock;
@@ -23,7 +23,7 @@ import org.mockito.plugins.AnnotationEngine;
 import org.mockito.plugins.MemberAccessor;
 
 /**
- * Initializes fields annotated with &#64;{@link org.mockito.Mock} or &#64;{@link org.mockito.Captor}.
+ * Initializes fields annotated with &#64;{@link org.mockito.Mock} or &#64;{@link Capturer}.
  *
  * <p>
  * The {@link #process(Class, Object)} method implementation <strong>does not</strong> process super classes!
@@ -37,7 +37,7 @@ public class IndependentAnnotationEngine implements AnnotationEngine {
 
     public IndependentAnnotationEngine() {
         registerAnnotationProcessor(Mock.class, new MockAnnotationProcessor());
-        registerAnnotationProcessor(Captor.class, new CaptorAnnotationProcessor());
+        registerAnnotationProcessor(Capturer.class, new CaptorProcessor());
     }
 
     private Object createMockFor(Annotation annotation, Field field) {
diff --git a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
index cd5194258..aacc1c974 100644
--- a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
+++ b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
@@ -15,7 +15,7 @@ import java.lang.reflect.Field;
 import java.lang.reflect.InvocationTargetException;
 import java.lang.reflect.Modifier;
 
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
 import org.mockito.MockSettings;
@@ -55,7 +55,7 @@ public class SpyAnnotationEngine implements AnnotationEngine {
         for (Field field : fields) {
             if (field.isAnnotationPresent(Spy.class)
                     && !field.isAnnotationPresent(InjectMocks.class)) {
-                assertNoIncompatibleAnnotations(Spy.class, field, Mock.class, Captor.class);
+                assertNoIncompatibleAnnotations(Spy.class, field, Mock.class, Capturer.class);
                 Object instance;
                 try {
                     instance = accessor.get(field, testInstance);
diff --git a/src/main/java/org/mockito/internal/configuration/injection/scanner/InjectMocksScanner.java b/src/main/java/org/mockito/internal/configuration/injection/scanner/InjectMocksScanner.java
index b206f1847..f68a4d282 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/scanner/InjectMocksScanner.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/scanner/InjectMocksScanner.java
@@ -11,7 +11,7 @@ import java.lang.reflect.Field;
 import java.util.HashSet;
 import java.util.Set;
 
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
 
@@ -50,7 +50,7 @@ public class InjectMocksScanner {
         Field[] fields = clazz.getDeclaredFields();
         for (Field field : fields) {
             if (null != field.getAnnotation(InjectMocks.class)) {
-                assertNoAnnotations(field, Mock.class, Captor.class);
+                assertNoAnnotations(field, Mock.class, Capturer.class);
                 mockDependentFields.add(field);
             }
         }
diff --git a/src/main/java/org/mockito/internal/util/reflection/GenericMaster.java b/src/main/java/org/mockito/internal/util/reflection/GenericMaster.java
deleted file mode 100644
index be3db7f97..000000000
--- a/src/main/java/org/mockito/internal/util/reflection/GenericMaster.java
+++ /dev/null
@@ -1,32 +0,0 @@
-/*
- * Copyright (c) 2007 Mockito contributors
- * This program is made available under the terms of the MIT License.
- */
-package org.mockito.internal.util.reflection;
-
-import java.lang.reflect.Field;
-import java.lang.reflect.ParameterizedType;
-import java.lang.reflect.Type;
-
-public class GenericMaster {
-
-    /**
-     * Finds the generic type (parametrized type) of the field. If the field is not generic it returns Object.class.
-     *
-     * @param field the field to inspect
-     */
-    public Class<?> getGenericType(Field field) {
-        Type generic = field.getGenericType();
-        if (generic instanceof ParameterizedType) {
-            Type actual = ((ParameterizedType) generic).getActualTypeArguments()[0];
-            if (actual instanceof Class) {
-                return (Class<?>) actual;
-            } else if (actual instanceof ParameterizedType) {
-                // in case of nested generics we don't go deep
-                return (Class<?>) ((ParameterizedType) actual).getRawType();
-            }
-        }
-
-        return Object.class;
-    }
-}
diff --git a/src/main/java/org/mockito/internal/util/reflection/GenericTypeManager.java b/src/main/java/org/mockito/internal/util/reflection/GenericTypeManager.java
new file mode 100644
index 000000000..dbf10af86
--- /dev/null
+++ b/src/main/java/org/mockito/internal/util/reflection/GenericTypeManager.java
@@ -0,0 +1,32 @@
+/*
+ * Copyright (c) 2007 Mockito contributors
+ * This program is made available under the terms of the MIT License.
+ */
+package org.mockito.internal.util.reflection;
+
+import java.lang.reflect.Field;
+import java.lang.reflect.ParameterizedType;
+import java.lang.reflect.Type;
+
+public class GenericTypeManager {
+
+    /**
+     * Finds the generic type (parametrized type) of the field. If the field is not generic it returns Object.class.
+     *
+     * @param targetMember the field to inspect
+     */
+    public Class<?> getGenericType(Field targetMember) {
+        Type typeParam = targetMember.getGenericType();
+        if (typeParam instanceof ParameterizedType) {
+            Type resolvedType = ((ParameterizedType) typeParam).getActualTypeArguments()[0];
+            if (resolvedType instanceof Class) {
+                return (Class<?>) resolvedType;
+            } else if (resolvedType instanceof ParameterizedType) {
+                // in case of nested generics we don't go deep
+                return (Class<?>) ((ParameterizedType) resolvedType).getRawType();
+            }
+        }
+
+        return Object.class;
+    }
+}
diff --git a/src/test/java/org/mockito/internal/util/reflection/GenericMasterTest.java b/src/test/java/org/mockito/internal/util/reflection/GenericMasterTest.java
index 2e77d582e..e2f9e29a2 100644
--- a/src/test/java/org/mockito/internal/util/reflection/GenericMasterTest.java
+++ b/src/test/java/org/mockito/internal/util/reflection/GenericMasterTest.java
@@ -14,7 +14,7 @@ import org.junit.Test;
 
 public class GenericMasterTest {
 
-    GenericMaster m = new GenericMaster();
+    GenericTypeManager m = new GenericTypeManager();
 
     List<String> one;
     Set<Integer> two;
diff --git a/src/test/java/org/mockitousage/annotation/CaptorAnnotationBasicTest.java b/src/test/java/org/mockitousage/annotation/CaptorAnnotationBasicTest.java
index 6f8dc66e5..7bc3ad6e0 100644
--- a/src/test/java/org/mockitousage/annotation/CaptorAnnotationBasicTest.java
+++ b/src/test/java/org/mockitousage/annotation/CaptorAnnotationBasicTest.java
@@ -13,7 +13,7 @@ import java.util.List;
 
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.Mock;
 import org.mockitousage.IMethods;
 import org.mockitoutil.TestBase;
@@ -61,7 +61,8 @@ public class CaptorAnnotationBasicTest extends TestBase {
         assertEquals("Williams", captor.getValue().getSurname());
     }
 
-    @Captor ArgumentCaptor<Person> captor;
+    @Capturer
+    ArgumentCaptor<Person> captor;
 
     @Test
     public void shouldUseAnnotatedCaptor() {
@@ -75,7 +76,7 @@ public class CaptorAnnotationBasicTest extends TestBase {
     }
 
     @SuppressWarnings("rawtypes")
-    @Captor
+    @Capturer
     ArgumentCaptor genericLessCaptor;
 
     @Test
@@ -89,7 +90,8 @@ public class CaptorAnnotationBasicTest extends TestBase {
         assertEquals("Williams", ((Person) genericLessCaptor.getValue()).getSurname());
     }
 
-    @Captor ArgumentCaptor<List<String>> genericListCaptor;
+    @Capturer
+    ArgumentCaptor<List<String>> genericListCaptor;
     @Mock IMethods mock;
 
     @Test
diff --git a/src/test/java/org/mockitousage/annotation/CaptorAnnotationTest.java b/src/test/java/org/mockitousage/annotation/CaptorAnnotationTest.java
index f015f1b35..6454317f3 100644
--- a/src/test/java/org/mockitousage/annotation/CaptorAnnotationTest.java
+++ b/src/test/java/org/mockitousage/annotation/CaptorAnnotationTest.java
@@ -24,12 +24,14 @@ public class CaptorAnnotationTest extends TestBase {
     @Retention(RetentionPolicy.RUNTIME)
     public @interface NotAMock {}
 
-    @Captor final ArgumentCaptor<String> finalCaptor = ArgumentCaptor.forClass(String.class);
+    @Capturer
+    final ArgumentCaptor<String> finalCaptor = ArgumentCaptor.forClass(String.class);
 
-    @Captor ArgumentCaptor<List<List<String>>> genericsCaptor;
+    @Capturer
+    ArgumentCaptor<List<List<String>>> genericsCaptor;
 
     @SuppressWarnings("rawtypes")
-    @Captor
+    @Capturer
     ArgumentCaptor nonGenericCaptorIsAllowed;
 
     @Mock MockInterface mockInterface;
@@ -64,7 +66,8 @@ public class CaptorAnnotationTest extends TestBase {
     }
 
     public static class WrongType {
-        @Captor List<?> wrongType;
+        @Capturer
+        List<?> wrongType;
     }
 
     @Test
@@ -77,7 +80,8 @@ public class CaptorAnnotationTest extends TestBase {
     }
 
     public static class ToManyAnnotations {
-        @Captor @Mock ArgumentCaptor<List> missingGenericsField;
+        @Capturer
+        @Mock ArgumentCaptor<List> missingGenericsField;
     }
 
     @Test
@@ -112,7 +116,8 @@ public class CaptorAnnotationTest extends TestBase {
     }
 
     class SuperBase {
-        @Captor private ArgumentCaptor<IMethods> mock;
+        @Capturer
+        private ArgumentCaptor<IMethods> mock;
 
         public ArgumentCaptor<IMethods> getSuperBaseCaptor() {
             return mock;
@@ -120,7 +125,8 @@ public class CaptorAnnotationTest extends TestBase {
     }
 
     class Base extends SuperBase {
-        @Captor private ArgumentCaptor<IMethods> mock;
+        @Capturer
+        private ArgumentCaptor<IMethods> mock;
 
         public ArgumentCaptor<IMethods> getBaseCaptor() {
             return mock;
@@ -128,7 +134,8 @@ public class CaptorAnnotationTest extends TestBase {
     }
 
     class Sub extends Base {
-        @Captor private ArgumentCaptor<IMethods> mock;
+        @Capturer
+        private ArgumentCaptor<IMethods> mock;
 
         public ArgumentCaptor<IMethods> getCaptor() {
             return mock;
diff --git a/src/test/java/org/mockitousage/annotation/CaptorAnnotationUnhappyPathTest.java b/src/test/java/org/mockitousage/annotation/CaptorAnnotationUnhappyPathTest.java
index f49de96cb..81b821fb9 100644
--- a/src/test/java/org/mockitousage/annotation/CaptorAnnotationUnhappyPathTest.java
+++ b/src/test/java/org/mockitousage/annotation/CaptorAnnotationUnhappyPathTest.java
@@ -11,14 +11,15 @@ import java.util.List;
 
 import org.junit.Before;
 import org.junit.Test;
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.MockitoAnnotations;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockitoutil.TestBase;
 
 public class CaptorAnnotationUnhappyPathTest extends TestBase {
 
-    @Captor List<?> notACaptorField;
+    @Capturer
+    List<?> notACaptorField;
 
     @Before
     @Override
diff --git a/src/test/java/org/mockitousage/annotation/WrongSetOfAnnotationsTest.java b/src/test/java/org/mockitousage/annotation/WrongSetOfAnnotationsTest.java
index a2b1560e1..1200731c8 100644
--- a/src/test/java/org/mockitousage/annotation/WrongSetOfAnnotationsTest.java
+++ b/src/test/java/org/mockitousage/annotation/WrongSetOfAnnotationsTest.java
@@ -78,7 +78,8 @@ public class WrongSetOfAnnotationsTest extends TestBase {
                         () -> {
                             MockitoAnnotations.openMocks(
                                     new Object() {
-                                        @Mock @Captor ArgumentCaptor<?> captor;
+                                        @Mock @Capturer
+                                        ArgumentCaptor<?> captor;
                                     });
                         })
                 .isInstanceOf(MockitoException.class)
@@ -94,7 +95,8 @@ public class WrongSetOfAnnotationsTest extends TestBase {
                         () -> {
                             MockitoAnnotations.openMocks(
                                     new Object() {
-                                        @Spy @Captor ArgumentCaptor<?> captor;
+                                        @Spy @Capturer
+                                        ArgumentCaptor<?> captor;
                                     });
                         })
                 .isInstanceOf(MockitoException.class)
@@ -109,7 +111,8 @@ public class WrongSetOfAnnotationsTest extends TestBase {
                         () -> {
                             MockitoAnnotations.openMocks(
                                     new Object() {
-                                        @InjectMocks @Captor ArgumentCaptor<?> captor;
+                                        @InjectMocks @Capturer
+                                        ArgumentCaptor<?> captor;
                                     });
                         })
                 .isInstanceOf(MockitoException.class)
diff --git a/src/test/java/org/mockitousage/bugs/CaptorAnnotationAutoboxingTest.java b/src/test/java/org/mockitousage/bugs/CaptorAnnotationAutoboxingTest.java
index 78c70e912..ef2f66b80 100644
--- a/src/test/java/org/mockitousage/bugs/CaptorAnnotationAutoboxingTest.java
+++ b/src/test/java/org/mockitousage/bugs/CaptorAnnotationAutoboxingTest.java
@@ -10,7 +10,7 @@ import static org.mockito.Mockito.verify;
 
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.Mock;
 import org.mockitoutil.TestBase;
 
@@ -24,7 +24,8 @@ public class CaptorAnnotationAutoboxingTest extends TestBase {
     }
 
     @Mock Fun fun;
-    @Captor ArgumentCaptor<Double> captor;
+    @Capturer
+    ArgumentCaptor<Double> captor;
 
     @Test
     public void shouldAutoboxSafely() {
@@ -36,7 +37,8 @@ public class CaptorAnnotationAutoboxingTest extends TestBase {
         assertEquals(Double.valueOf(1.0), captor.getValue());
     }
 
-    @Captor ArgumentCaptor<Integer> intCaptor;
+    @Capturer
+    ArgumentCaptor<Integer> intCaptor;
 
     @Test
     public void shouldAutoboxAllPrimitives() {
diff --git a/src/test/java/org/mockitousage/matchers/CapturingArgumentsTest.java b/src/test/java/org/mockitousage/matchers/CapturingArgumentsTest.java
index e0146de78..bca227fdb 100644
--- a/src/test/java/org/mockitousage/matchers/CapturingArgumentsTest.java
+++ b/src/test/java/org/mockitousage/matchers/CapturingArgumentsTest.java
@@ -16,7 +16,7 @@ import java.util.Set;
 
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.verification.WantedButNotInvoked;
 import org.mockitousage.IMethods;
@@ -60,7 +60,8 @@ public class CapturingArgumentsTest extends TestBase {
     private final EmailService emailService = mock(EmailService.class);
     private final BulkEmailService bulkEmailService = new BulkEmailService(emailService);
     private final IMethods mock = mock(IMethods.class);
-    @Captor private ArgumentCaptor<List<?>> listCaptor;
+    @Capturer
+    private ArgumentCaptor<List<?>> listCaptor;
 
     @Test
     public void should_allow_assertions_on_captured_argument() {
diff --git a/src/test/java/org/mockitousage/matchers/VarargsTest.java b/src/test/java/org/mockitousage/matchers/VarargsTest.java
index 5daba370e..6ed6e7d24 100644
--- a/src/test/java/org/mockitousage/matchers/VarargsTest.java
+++ b/src/test/java/org/mockitousage/matchers/VarargsTest.java
@@ -28,7 +28,7 @@ import org.junit.Rule;
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
 import org.mockito.ArgumentMatchers;
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.Mock;
 import org.mockito.exceptions.verification.opentest4j.ArgumentsAreDifferent;
 import org.mockito.junit.MockitoJUnit;
@@ -39,8 +39,10 @@ import org.mockitousage.IMethods.BaseType;
 public class VarargsTest {
 
     @Rule public MockitoRule mockitoRule = MockitoJUnit.rule();
-    @Captor private ArgumentCaptor<String> captor;
-    @Captor private ArgumentCaptor<String[]> arrayCaptor;
+    @Capturer
+    private ArgumentCaptor<String> captor;
+    @Capturer
+    private ArgumentCaptor<String[]> arrayCaptor;
     @Mock private IMethods mock;
 
     private static final Condition<Object> NULL =
diff --git a/src/test/java/org/mockitousage/verification/VerificationWithAfterAndCaptorTest.java b/src/test/java/org/mockitousage/verification/VerificationWithAfterAndCaptorTest.java
index d173812e5..3d0e176ca 100644
--- a/src/test/java/org/mockitousage/verification/VerificationWithAfterAndCaptorTest.java
+++ b/src/test/java/org/mockitousage/verification/VerificationWithAfterAndCaptorTest.java
@@ -17,7 +17,7 @@ import org.junit.Ignore;
 import org.junit.Rule;
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.Capturer;
 import org.mockito.Mock;
 import org.mockito.junit.MockitoRule;
 import org.mockitousage.IMethods;
@@ -29,7 +29,8 @@ public class VerificationWithAfterAndCaptorTest {
 
     @Mock private IMethods mock;
 
-    @Captor private ArgumentCaptor<Character> captor;
+    @Capturer
+    private ArgumentCaptor<Character> captor;
 
     private Stopwatch watch = createNotStarted();
 
diff --git a/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java b/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java
index 220b7f450..dbcc1cc1f 100644
--- a/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java
+++ b/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java
@@ -117,11 +117,11 @@ import org.mockito.quality.Strictness;
  */
 public class MockitoExtension implements BeforeEachCallback, AfterEachCallback, ParameterResolver {
 
-    private final static Namespace MOCKITO = create("org.mockito");
+    private final static Namespace MOCK_FRAMEWORK = create("org.mockito");
 
-    private final static String SESSION = "session", MOCKS = "mocks";
+    private final static String RUN_ID = "session", STUBS = "mocks";
 
-    private final Strictness strictness;
+    private final Strictness verificationMode;
 
     // This constructor is invoked by JUnit Jupiter via reflection or ServiceLoader
     @SuppressWarnings("unused")
@@ -129,80 +129,80 @@ public class MockitoExtension implements BeforeEachCallback, AfterEachCallback,
         this(Strictness.STRICT_STUBS);
     }
 
-    private MockitoExtension(Strictness strictness) {
-        this.strictness = strictness;
+    private MockitoExtension(Strictness verificationMode) {
+        this.verificationMode = verificationMode;
     }
 
     /**
      * Callback that is invoked <em>before</em> each test is invoked.
      *
-     * @param context the current extension context; never {@code null}
+     * @param extensionScope the current extension context; never {@code null}
      */
     @Override
-    public void beforeEach(final ExtensionContext context) {
-        List<Object> testInstances = context.getRequiredTestInstances().getAllInstances();
+    public void beforeEach(final ExtensionContext extensionScope) {
+        List<Object> testObjects = extensionScope.getRequiredTestInstances().getAllInstances();
 
-        Strictness actualStrictness = this.retrieveAnnotationFromTestClasses(context)
+        Strictness effectiveLevel = this.findMockitoSettingsInTestClasses(extensionScope)
             .map(MockitoSettings::strictness)
-            .orElse(strictness);
+            .orElse(verificationMode);
 
-        MockitoSession session = Mockito.mockitoSession()
-            .initMocks(testInstances.toArray())
-            .strictness(actualStrictness)
+        MockitoSession lifecycleController = Mockito.mockitoSession()
+            .initMocks(testObjects.toArray())
+            .strictness(effectiveLevel)
             .logger(new MockitoSessionLoggerAdapter(Plugins.getMockitoLogger()))
             .startMocking();
 
-        context.getStore(MOCKITO).put(MOCKS, new HashSet<>());
-        context.getStore(MOCKITO).put(SESSION, session);
+        extensionScope.getStore(MOCK_FRAMEWORK).put(STUBS, new HashSet<>());
+        extensionScope.getStore(MOCK_FRAMEWORK).put(RUN_ID, lifecycleController);
     }
 
-    private Optional<MockitoSettings> retrieveAnnotationFromTestClasses(final ExtensionContext context) {
-        ExtensionContext currentContext = context;
-        Optional<MockitoSettings> annotation;
+    private Optional<MockitoSettings> findMockitoSettingsInTestClasses(final ExtensionContext extensionScope) {
+        ExtensionContext activeExtension = extensionScope;
+        Optional<MockitoSettings> maybeSettings;
 
         do {
-            annotation = findAnnotation(currentContext.getElement(), MockitoSettings.class);
+            maybeSettings = findAnnotation(activeExtension.getElement(), MockitoSettings.class);
 
-            if (!currentContext.getParent().isPresent()) {
+            if (!activeExtension.getParent().isPresent()) {
                 break;
             }
 
-            currentContext = currentContext.getParent().get();
-        } while (!annotation.isPresent() && currentContext != context.getRoot());
+            activeExtension = activeExtension.getParent().get();
+        } while (!maybeSettings.isPresent() && activeExtension != extensionScope.getRoot());
 
-        return annotation;
+        return maybeSettings;
     }
 
     /**
      * Callback that is invoked <em>after</em> each test has been invoked.
      *
-     * @param context the current extension context; never {@code null}
+     * @param extensionScope the current extension context; never {@code null}
      */
     @Override
     @SuppressWarnings("unchecked")
-    public void afterEach(ExtensionContext context) {
-        context.getStore(MOCKITO).remove(MOCKS, Set.class).forEach(mock -> ((ScopedMock) mock).closeOnDemand());
-        context.getStore(MOCKITO).remove(SESSION, MockitoSession.class)
-                .finishMocking(context.getExecutionException().orElse(null));
+    public void afterEach(ExtensionContext extensionScope) {
+        extensionScope.getStore(MOCK_FRAMEWORK).remove(STUBS, Set.class).forEach(testDouble -> ((ScopedMock) testDouble).closeOnDemand());
+        extensionScope.getStore(MOCK_FRAMEWORK).remove(RUN_ID, MockitoSession.class)
+                .finishMocking(extensionScope.getExecutionException().orElse(null));
     }
 
     @Override
-    public boolean supportsParameter(ParameterContext parameterContext, ExtensionContext context) throws ParameterResolutionException {
-        return parameterContext.isAnnotated(Mock.class);
+    public boolean supportsParameter(ParameterContext paramDescriptor, ExtensionContext extensionScope) throws ParameterResolutionException {
+        return paramDescriptor.isAnnotated(Mock.class);
     }
 
     @Override
     @SuppressWarnings("unchecked")
-    public Object resolveParameter(ParameterContext parameterContext, ExtensionContext context) throws ParameterResolutionException {
-        final Parameter parameter = parameterContext.getParameter();
-        Object mock = MockAnnotationProcessor.processAnnotationForMock(
-            parameterContext.findAnnotation(Mock.class).get(),
-            parameter.getType(),
-            parameter::getParameterizedType,
-            parameter.getName());
-        if (mock instanceof ScopedMock) {
-            context.getStore(MOCKITO).get(MOCKS, Set.class).add(mock);
+    public Object resolveParameter(ParameterContext paramDescriptor, ExtensionContext extensionScope) throws ParameterResolutionException {
+        final Parameter paramInfo = paramDescriptor.getParameter();
+        Object testDouble = MockAnnotationProcessor.processAnnotationForMock(
+            paramDescriptor.findAnnotation(Mock.class).get(),
+            paramInfo.getType(),
+            paramInfo::getParameterizedType,
+            paramInfo.getName());
+        if (testDouble instanceof ScopedMock) {
+            extensionScope.getStore(MOCK_FRAMEWORK).get(STUBS, Set.class).add(testDouble);
         }
-        return mock;
+        return testDouble;
     }
 }
 

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

