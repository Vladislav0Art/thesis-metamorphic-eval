#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout edc624371009ce981bbc11b7d125ff4e359cff7e

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/ArgumentCaptor.java b/src/main/java/org/mockito/ArgumentCaptor.java
index 2fdeb628d..f4abda00f 100644
--- a/src/main/java/org/mockito/ArgumentCaptor.java
+++ b/src/main/java/org/mockito/ArgumentCaptor.java
@@ -9,6 +9,7 @@ import static org.mockito.internal.util.Primitives.defaultValue;
 import java.util.List;
 
 import org.mockito.internal.matchers.CapturingMatcher;
+import org.mockito.plugins.Captor;
 
 /**
  * Use it to capture argument values for further assertions.
diff --git a/src/main/java/org/mockito/Mockito.java b/src/main/java/org/mockito/Mockito.java
index ee5a13303..fe0aa5338 100644
--- a/src/main/java/org/mockito/Mockito.java
+++ b/src/main/java/org/mockito/Mockito.java
@@ -22,6 +22,7 @@ import org.mockito.junit.MockitoRule;
 import org.mockito.listeners.VerificationStartedEvent;
 import org.mockito.listeners.VerificationStartedListener;
 import org.mockito.mock.SerializableMode;
+import org.mockito.plugins.Captor;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockitoPlugins;
 import org.mockito.quality.MockitoHint;
diff --git a/src/main/java/org/mockito/MockitoAnnotations.java b/src/main/java/org/mockito/MockitoAnnotations.java
index 5857478ca..e0e02d966 100644
--- a/src/main/java/org/mockito/MockitoAnnotations.java
+++ b/src/main/java/org/mockito/MockitoAnnotations.java
@@ -10,6 +10,7 @@ import org.mockito.exceptions.base.MockitoException;
 import org.mockito.internal.configuration.GlobalConfiguration;
 import org.mockito.junit.MockitoJUnitRunner;
 import org.mockito.plugins.AnnotationEngine;
+import org.mockito.plugins.Captor;
 
 /**
  * MockitoAnnotations.openMocks(this); initializes fields annotated with Mockito annotations.
diff --git a/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java b/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
index a7950da9f..424f4c206 100644
--- a/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
+++ b/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
@@ -13,7 +13,8 @@ import java.util.HashMap;
 import java.util.List;
 import java.util.Map;
 
-import org.mockito.Captor;
+import org.mockito.internal.util.CaptorAnnotationProcessor;
+import org.mockito.plugins.Captor;
 import org.mockito.Mock;
 import org.mockito.MockitoAnnotations;
 import org.mockito.ScopedMock;
@@ -23,7 +24,7 @@ import org.mockito.plugins.AnnotationEngine;
 import org.mockito.plugins.MemberAccessor;
 
 /**
- * Initializes fields annotated with &#64;{@link org.mockito.Mock} or &#64;{@link org.mockito.Captor}.
+ * Initializes fields annotated with &#64;{@link org.mockito.Mock} or &#64;{@link Captor}.
  *
  * <p>
  * The {@link #process(Class, Object)} method implementation <strong>does not</strong> process super classes!
diff --git a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
index cd5194258..425b70891 100644
--- a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
+++ b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
@@ -15,7 +15,7 @@ import java.lang.reflect.Field;
 import java.lang.reflect.InvocationTargetException;
 import java.lang.reflect.Modifier;
 
-import org.mockito.Captor;
+import org.mockito.plugins.Captor;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
 import org.mockito.MockSettings;
diff --git a/src/main/java/org/mockito/internal/configuration/injection/scanner/InjectMocksScanner.java b/src/main/java/org/mockito/internal/configuration/injection/scanner/InjectMocksScanner.java
index b206f1847..7266a3988 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/scanner/InjectMocksScanner.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/scanner/InjectMocksScanner.java
@@ -11,7 +11,7 @@ import java.lang.reflect.Field;
 import java.util.HashSet;
 import java.util.Set;
 
-import org.mockito.Captor;
+import org.mockito.plugins.Captor;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
 
diff --git a/src/main/java/org/mockito/internal/configuration/CaptorAnnotationProcessor.java b/src/main/java/org/mockito/internal/util/CaptorAnnotationProcessor.java
similarity index 88%
rename from src/main/java/org/mockito/internal/configuration/CaptorAnnotationProcessor.java
rename to src/main/java/org/mockito/internal/util/CaptorAnnotationProcessor.java
index 600583be5..7302b08c5 100644
--- a/src/main/java/org/mockito/internal/configuration/CaptorAnnotationProcessor.java
+++ b/src/main/java/org/mockito/internal/util/CaptorAnnotationProcessor.java
@@ -2,14 +2,14 @@
  * Copyright (c) 2007 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.internal.configuration;
+package org.mockito.internal.util;
 
 import java.lang.reflect.Field;
 
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.internal.configuration.FieldAnnotationProcessor;
+import org.mockito.plugins.Captor;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.util.reflection.GenericMaster;
 
 /**
  * Instantiate {@link ArgumentCaptor} a field annotated by &#64;Captor.
diff --git a/src/main/java/org/mockito/internal/util/reflection/GenericMaster.java b/src/main/java/org/mockito/internal/util/GenericMaster.java
similarity index 95%
rename from src/main/java/org/mockito/internal/util/reflection/GenericMaster.java
rename to src/main/java/org/mockito/internal/util/GenericMaster.java
index be3db7f97..54db8e2d9 100644
--- a/src/main/java/org/mockito/internal/util/reflection/GenericMaster.java
+++ b/src/main/java/org/mockito/internal/util/GenericMaster.java
@@ -2,7 +2,7 @@
  * Copyright (c) 2007 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.internal.util.reflection;
+package org.mockito.internal.util;
 
 import java.lang.reflect.Field;
 import java.lang.reflect.ParameterizedType;
diff --git a/src/main/java/org/mockito/Captor.java b/src/main/java/org/mockito/plugins/Captor.java
similarity index 95%
rename from src/main/java/org/mockito/Captor.java
rename to src/main/java/org/mockito/plugins/Captor.java
index 0de9f72b2..f4aa92fad 100644
--- a/src/main/java/org/mockito/Captor.java
+++ b/src/main/java/org/mockito/plugins/Captor.java
@@ -2,7 +2,9 @@
  * Copyright (c) 2007 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito;
+package org.mockito.plugins;
+
+import org.mockito.ArgumentCaptor;
 
 import java.lang.annotation.Documented;
 import java.lang.annotation.ElementType;
diff --git a/src/test/java/org/mockito/internal/util/reflection/GenericMasterTest.java b/src/test/java/org/mockito/internal/util/reflection/GenericMasterTest.java
index 2e77d582e..e18e3ef25 100644
--- a/src/test/java/org/mockito/internal/util/reflection/GenericMasterTest.java
+++ b/src/test/java/org/mockito/internal/util/reflection/GenericMasterTest.java
@@ -11,6 +11,7 @@ import java.lang.reflect.Type;
 import java.util.*;
 
 import org.junit.Test;
+import org.mockito.internal.util.GenericMaster;
 
 public class GenericMasterTest {
 
diff --git a/src/test/java/org/mockitousage/annotation/CaptorAnnotationBasicTest.java b/src/test/java/org/mockitousage/annotation/CaptorAnnotationBasicTest.java
index 6f8dc66e5..11e2bb496 100644
--- a/src/test/java/org/mockitousage/annotation/CaptorAnnotationBasicTest.java
+++ b/src/test/java/org/mockitousage/annotation/CaptorAnnotationBasicTest.java
@@ -13,7 +13,7 @@ import java.util.List;
 
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.plugins.Captor;
 import org.mockito.Mock;
 import org.mockitousage.IMethods;
 import org.mockitoutil.TestBase;
diff --git a/src/test/java/org/mockitousage/annotation/CaptorAnnotationTest.java b/src/test/java/org/mockitousage/annotation/CaptorAnnotationTest.java
index f015f1b35..68b1ad800 100644
--- a/src/test/java/org/mockitousage/annotation/CaptorAnnotationTest.java
+++ b/src/test/java/org/mockitousage/annotation/CaptorAnnotationTest.java
@@ -16,6 +16,7 @@ import java.util.Set;
 import org.junit.Test;
 import org.mockito.*;
 import org.mockito.exceptions.base.MockitoException;
+import org.mockito.plugins.Captor;
 import org.mockitousage.IMethods;
 import org.mockitoutil.TestBase;
 
@@ -24,7 +25,8 @@ public class CaptorAnnotationTest extends TestBase {
     @Retention(RetentionPolicy.RUNTIME)
     public @interface NotAMock {}
 
-    @Captor final ArgumentCaptor<String> finalCaptor = ArgumentCaptor.forClass(String.class);
+    @Captor
+    final ArgumentCaptor<String> finalCaptor = ArgumentCaptor.forClass(String.class);
 
     @Captor ArgumentCaptor<List<List<String>>> genericsCaptor;
 
diff --git a/src/test/java/org/mockitousage/annotation/CaptorAnnotationUnhappyPathTest.java b/src/test/java/org/mockitousage/annotation/CaptorAnnotationUnhappyPathTest.java
index f49de96cb..756951488 100644
--- a/src/test/java/org/mockitousage/annotation/CaptorAnnotationUnhappyPathTest.java
+++ b/src/test/java/org/mockitousage/annotation/CaptorAnnotationUnhappyPathTest.java
@@ -11,7 +11,7 @@ import java.util.List;
 
 import org.junit.Before;
 import org.junit.Test;
-import org.mockito.Captor;
+import org.mockito.plugins.Captor;
 import org.mockito.MockitoAnnotations;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockitoutil.TestBase;
diff --git a/src/test/java/org/mockitousage/annotation/WrongSetOfAnnotationsTest.java b/src/test/java/org/mockitousage/annotation/WrongSetOfAnnotationsTest.java
index a2b1560e1..442f44ae6 100644
--- a/src/test/java/org/mockitousage/annotation/WrongSetOfAnnotationsTest.java
+++ b/src/test/java/org/mockitousage/annotation/WrongSetOfAnnotationsTest.java
@@ -13,6 +13,7 @@ import org.assertj.core.api.Assertions;
 import org.junit.Test;
 import org.mockito.*;
 import org.mockito.exceptions.base.MockitoException;
+import org.mockito.plugins.Captor;
 import org.mockitoutil.TestBase;
 
 public class WrongSetOfAnnotationsTest extends TestBase {
@@ -78,7 +79,8 @@ public class WrongSetOfAnnotationsTest extends TestBase {
                         () -> {
                             MockitoAnnotations.openMocks(
                                     new Object() {
-                                        @Mock @Captor ArgumentCaptor<?> captor;
+                                        @Mock @Captor
+                                        ArgumentCaptor<?> captor;
                                     });
                         })
                 .isInstanceOf(MockitoException.class)
diff --git a/src/test/java/org/mockitousage/bugs/CaptorAnnotationAutoboxingTest.java b/src/test/java/org/mockitousage/bugs/CaptorAnnotationAutoboxingTest.java
index 78c70e912..17c4ce7e1 100644
--- a/src/test/java/org/mockitousage/bugs/CaptorAnnotationAutoboxingTest.java
+++ b/src/test/java/org/mockitousage/bugs/CaptorAnnotationAutoboxingTest.java
@@ -10,7 +10,7 @@ import static org.mockito.Mockito.verify;
 
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.plugins.Captor;
 import org.mockito.Mock;
 import org.mockitoutil.TestBase;
 
diff --git a/src/test/java/org/mockitousage/matchers/CapturingArgumentsTest.java b/src/test/java/org/mockitousage/matchers/CapturingArgumentsTest.java
index e0146de78..89d926e61 100644
--- a/src/test/java/org/mockitousage/matchers/CapturingArgumentsTest.java
+++ b/src/test/java/org/mockitousage/matchers/CapturingArgumentsTest.java
@@ -16,7 +16,7 @@ import java.util.Set;
 
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.plugins.Captor;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.verification.WantedButNotInvoked;
 import org.mockitousage.IMethods;
diff --git a/src/test/java/org/mockitousage/matchers/VarargsTest.java b/src/test/java/org/mockitousage/matchers/VarargsTest.java
index 5daba370e..f9e4dbc42 100644
--- a/src/test/java/org/mockitousage/matchers/VarargsTest.java
+++ b/src/test/java/org/mockitousage/matchers/VarargsTest.java
@@ -28,7 +28,7 @@ import org.junit.Rule;
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
 import org.mockito.ArgumentMatchers;
-import org.mockito.Captor;
+import org.mockito.plugins.Captor;
 import org.mockito.Mock;
 import org.mockito.exceptions.verification.opentest4j.ArgumentsAreDifferent;
 import org.mockito.junit.MockitoJUnit;
diff --git a/src/test/java/org/mockitousage/verification/VerificationWithAfterAndCaptorTest.java b/src/test/java/org/mockitousage/verification/VerificationWithAfterAndCaptorTest.java
index d173812e5..95a00ff03 100644
--- a/src/test/java/org/mockitousage/verification/VerificationWithAfterAndCaptorTest.java
+++ b/src/test/java/org/mockitousage/verification/VerificationWithAfterAndCaptorTest.java
@@ -17,7 +17,7 @@ import org.junit.Ignore;
 import org.junit.Rule;
 import org.junit.Test;
 import org.mockito.ArgumentCaptor;
-import org.mockito.Captor;
+import org.mockito.plugins.Captor;
 import org.mockito.Mock;
 import org.mockito.junit.MockitoRule;
 import org.mockitousage.IMethods;
diff --git a/subprojects/extTest/src/test/java/org/mockitousage/plugins/logger/MockitoLoggerTest.java b/subprojects/extTest/src/test/java/org/mockitousage/plugins/logger/MockitoLoggerTest.java
index c1cce5122..290d062a3 100644
--- a/subprojects/extTest/src/test/java/org/mockitousage/plugins/logger/MockitoLoggerTest.java
+++ b/subprojects/extTest/src/test/java/org/mockitousage/plugins/logger/MockitoLoggerTest.java
@@ -10,7 +10,7 @@ import org.junit.jupiter.api.AfterAll;
 import org.junit.jupiter.api.BeforeAll;
 import org.junit.jupiter.api.Test;
 import org.junit.jupiter.api.extension.ExtendWith;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 import org.mockito.junit.jupiter.MockitoSettings;
 import org.mockito.quality.Strictness;
 
diff --git a/subprojects/extTest/src/test/java/org/mockitousage/plugins/resolver/MockResolverTest.java b/subprojects/extTest/src/test/java/org/mockitousage/plugins/resolver/MockResolverTest.java
index bd51fe6dc..c439e6ec9 100644
--- a/subprojects/extTest/src/test/java/org/mockitousage/plugins/resolver/MockResolverTest.java
+++ b/subprojects/extTest/src/test/java/org/mockitousage/plugins/resolver/MockResolverTest.java
@@ -6,7 +6,7 @@ package org.mockitousage.plugins.resolver;
 
 import org.junit.jupiter.api.Test;
 import org.junit.jupiter.api.extension.ExtendWith;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 import org.mockito.junit.jupiter.MockitoSettings;
 import org.mockito.quality.Strictness;
 
diff --git a/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoSettings.java b/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoSettings.java
index ee06b02af..baf51a97c 100644
--- a/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoSettings.java
+++ b/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoSettings.java
@@ -5,6 +5,7 @@
 package org.mockito.junit.jupiter;
 
 import org.junit.jupiter.api.extension.ExtendWith;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 import org.mockito.quality.Strictness;
 
 import java.lang.annotation.Inherited;
diff --git a/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java b/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/extensions/MockitoExtension.java
similarity index 98%
rename from subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java
rename to subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/extensions/MockitoExtension.java
index 220b7f450..90c4fd7c2 100644
--- a/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java
+++ b/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/extensions/MockitoExtension.java
@@ -2,7 +2,7 @@
  * Copyright (c) 2018 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.junit.jupiter;
+package org.mockito.junit.jupiter.extensions;
 
 import static org.junit.jupiter.api.extension.ExtensionContext.Namespace.create;
 import static org.junit.platform.commons.support.AnnotationSupport.findAnnotation;
@@ -28,6 +28,7 @@ import org.mockito.internal.configuration.MockAnnotationProcessor;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.session.MockitoSessionLoggerAdapter;
 import org.mockito.junit.MockitoJUnitRunner;
+import org.mockito.junit.jupiter.MockitoSettings;
 import org.mockito.quality.Strictness;
 
 /**
@@ -123,14 +124,41 @@ public class MockitoExtension implements BeforeEachCallback, AfterEachCallback,
 
     private final Strictness strictness;
 
-    // This constructor is invoked by JUnit Jupiter via reflection or ServiceLoader
-    @SuppressWarnings("unused")
-    public MockitoExtension() {
-        this(Strictness.STRICT_STUBS);
+    @Override
+    public boolean supportsParameter(ParameterContext parameterContext, ExtensionContext context) throws ParameterResolutionException {
+        return parameterContext.isAnnotated(Mock.class);
     }
 
-    private MockitoExtension(Strictness strictness) {
-        this.strictness = strictness;
+    private Optional<MockitoSettings> retrieveAnnotationFromTestClasses(final ExtensionContext context) {
+        ExtensionContext currentContext = context;
+        Optional<MockitoSettings> annotation;
+
+        do {
+            annotation = findAnnotation(currentContext.getElement(), MockitoSettings.class);
+
+            if (!currentContext.getParent().isPresent()) {
+                break;
+            }
+
+            currentContext = currentContext.getParent().get();
+        } while (!annotation.isPresent() && currentContext != context.getRoot());
+
+        return annotation;
+    }
+
+    @Override
+    @SuppressWarnings("unchecked")
+    public Object resolveParameter(ParameterContext parameterContext, ExtensionContext context) throws ParameterResolutionException {
+        final Parameter parameter = parameterContext.getParameter();
+        Object mock = MockAnnotationProcessor.processAnnotationForMock(
+            parameterContext.findAnnotation(Mock.class).get(),
+            parameter.getType(),
+            parameter::getParameterizedType,
+            parameter.getName());
+        if (mock instanceof ScopedMock) {
+            context.getStore(MOCKITO).get(MOCKS, Set.class).add(mock);
+        }
+        return mock;
     }
 
     /**
@@ -156,23 +184,6 @@ public class MockitoExtension implements BeforeEachCallback, AfterEachCallback,
         context.getStore(MOCKITO).put(SESSION, session);
     }
 
-    private Optional<MockitoSettings> retrieveAnnotationFromTestClasses(final ExtensionContext context) {
-        ExtensionContext currentContext = context;
-        Optional<MockitoSettings> annotation;
-
-        do {
-            annotation = findAnnotation(currentContext.getElement(), MockitoSettings.class);
-
-            if (!currentContext.getParent().isPresent()) {
-                break;
-            }
-
-            currentContext = currentContext.getParent().get();
-        } while (!annotation.isPresent() && currentContext != context.getRoot());
-
-        return annotation;
-    }
-
     /**
      * Callback that is invoked <em>after</em> each test has been invoked.
      *
@@ -186,23 +197,13 @@ public class MockitoExtension implements BeforeEachCallback, AfterEachCallback,
                 .finishMocking(context.getExecutionException().orElse(null));
     }
 
-    @Override
-    public boolean supportsParameter(ParameterContext parameterContext, ExtensionContext context) throws ParameterResolutionException {
-        return parameterContext.isAnnotated(Mock.class);
+    // This constructor is invoked by JUnit Jupiter via reflection or ServiceLoader
+    @SuppressWarnings("unused")
+    public MockitoExtension() {
+        this(Strictness.STRICT_STUBS);
     }
 
-    @Override
-    @SuppressWarnings("unchecked")
-    public Object resolveParameter(ParameterContext parameterContext, ExtensionContext context) throws ParameterResolutionException {
-        final Parameter parameter = parameterContext.getParameter();
-        Object mock = MockAnnotationProcessor.processAnnotationForMock(
-            parameterContext.findAnnotation(Mock.class).get(),
-            parameter.getType(),
-            parameter::getParameterizedType,
-            parameter.getName());
-        if (mock instanceof ScopedMock) {
-            context.getStore(MOCKITO).get(MOCKS, Set.class).add(mock);
-        }
-        return mock;
+    private MockitoExtension(Strictness strictness) {
+        this.strictness = strictness;
     }
 }
diff --git a/subprojects/junit-jupiter/src/test/java/org/mockitousage/GenericTypeMockMultipleMatchesTest.java b/subprojects/junit-jupiter/src/test/java/org/mockitousage/GenericTypeMockMultipleMatchesTest.java
index 323008eb6..32591ad78 100644
--- a/subprojects/junit-jupiter/src/test/java/org/mockitousage/GenericTypeMockMultipleMatchesTest.java
+++ b/subprojects/junit-jupiter/src/test/java/org/mockitousage/GenericTypeMockMultipleMatchesTest.java
@@ -17,7 +17,7 @@ import org.junit.jupiter.api.extension.ExtensionContext;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 
 /**
  * Verify that a {@link MockitoException} is thrown when there are multiple {@link Mock} fields that
diff --git a/subprojects/junit-jupiter/src/test/java/org/mockitousage/GenericTypeMockTest.java b/subprojects/junit-jupiter/src/test/java/org/mockitousage/GenericTypeMockTest.java
index cb3b835c7..24cd9cb5c 100644
--- a/subprojects/junit-jupiter/src/test/java/org/mockitousage/GenericTypeMockTest.java
+++ b/subprojects/junit-jupiter/src/test/java/org/mockitousage/GenericTypeMockTest.java
@@ -28,7 +28,7 @@ import org.junit.jupiter.api.Test;
 import org.junit.jupiter.api.extension.ExtendWith;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 
 /**
  * Tests that verify Mockito can discern mocks by generic types, so if there are multiple mock candidates
diff --git a/subprojects/junit-jupiter/src/test/java/org/mockitousage/InjectMocksTest.java b/subprojects/junit-jupiter/src/test/java/org/mockitousage/InjectMocksTest.java
index 0f2523d9b..f9a996422 100644
--- a/subprojects/junit-jupiter/src/test/java/org/mockitousage/InjectMocksTest.java
+++ b/subprojects/junit-jupiter/src/test/java/org/mockitousage/InjectMocksTest.java
@@ -8,7 +8,7 @@ import org.junit.jupiter.api.Test;
 import org.junit.jupiter.api.extension.ExtendWith;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 
 import static org.assertj.core.api.Assertions.assertThat;
 
diff --git a/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java b/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
index 31abe2e61..90d9b73c3 100644
--- a/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
+++ b/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
@@ -12,7 +12,7 @@ import org.mockito.InjectMocks;
 import org.mockito.Mock;
 import org.mockito.Mockito;
 import org.mockito.internal.util.MockUtil;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 
 import static org.assertj.core.api.Assertions.assertThat;
 
diff --git a/subprojects/junit-jupiter/src/test/java/org/mockitousage/MultiLevelNestedTest.java b/subprojects/junit-jupiter/src/test/java/org/mockitousage/MultiLevelNestedTest.java
index 58a42f97e..84664ab30 100644
--- a/subprojects/junit-jupiter/src/test/java/org/mockitousage/MultiLevelNestedTest.java
+++ b/subprojects/junit-jupiter/src/test/java/org/mockitousage/MultiLevelNestedTest.java
@@ -8,7 +8,7 @@ import org.junit.jupiter.api.Nested;
 import org.junit.jupiter.api.Test;
 import org.junit.jupiter.api.extension.ExtendWith;
 import org.mockito.Mock;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 
 import static org.assertj.core.api.Assertions.assertThat;
 
diff --git a/subprojects/junit-jupiter/src/test/java/org/mockitousage/StrictnessTest.java b/subprojects/junit-jupiter/src/test/java/org/mockitousage/StrictnessTest.java
index 1b63d66cc..cf263e6bb 100644
--- a/subprojects/junit-jupiter/src/test/java/org/mockitousage/StrictnessTest.java
+++ b/subprojects/junit-jupiter/src/test/java/org/mockitousage/StrictnessTest.java
@@ -17,7 +17,7 @@ import org.junit.platform.launcher.core.LauncherFactory;
 import org.mockito.Mock;
 import org.mockito.Mockito;
 import org.mockito.exceptions.misusing.UnnecessaryStubbingException;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 import org.mockito.junit.jupiter.MockitoSettings;
 import org.mockito.quality.Strictness;
 
diff --git a/subprojects/junitJupiterExtensionTest/src/test/resources/META-INF/services/org.junit.jupiter.api.extension.Extension b/subprojects/junitJupiterExtensionTest/src/test/resources/META-INF/services/org.junit.jupiter.api.extension.Extension
index 02593efe3..7fe7d738b 100644
--- a/subprojects/junitJupiterExtensionTest/src/test/resources/META-INF/services/org.junit.jupiter.api.extension.Extension
+++ b/subprojects/junitJupiterExtensionTest/src/test/resources/META-INF/services/org.junit.jupiter.api.extension.Extension
@@ -1 +1 @@
-org.mockito.junit.jupiter.MockitoExtension
+org.mockito.junit.jupiter.extensions.MockitoExtension
diff --git a/subprojects/junitJupiterInlineMockMakerExtensionTest/src/test/java/org/mockitousage/CloseOnDemandTest.java b/subprojects/junitJupiterInlineMockMakerExtensionTest/src/test/java/org/mockitousage/CloseOnDemandTest.java
index cfb66cf96..ca650817b 100644
--- a/subprojects/junitJupiterInlineMockMakerExtensionTest/src/test/java/org/mockitousage/CloseOnDemandTest.java
+++ b/subprojects/junitJupiterInlineMockMakerExtensionTest/src/test/java/org/mockitousage/CloseOnDemandTest.java
@@ -9,7 +9,7 @@ import org.junit.jupiter.api.extension.ExtendWith;
 import org.mockito.Mock;
 import org.mockito.MockedConstruction;
 import org.mockito.MockedStatic;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 
 import static org.junit.jupiter.api.Assertions.assertNotNull;
 
diff --git a/subprojects/junitJupiterInlineMockMakerExtensionTest/src/test/resources/META-INF/services/org.junit.jupiter.api.extension.Extension b/subprojects/junitJupiterInlineMockMakerExtensionTest/src/test/resources/META-INF/services/org.junit.jupiter.api.extension.Extension
index 02593efe3..7fe7d738b 100644
--- a/subprojects/junitJupiterInlineMockMakerExtensionTest/src/test/resources/META-INF/services/org.junit.jupiter.api.extension.Extension
+++ b/subprojects/junitJupiterInlineMockMakerExtensionTest/src/test/resources/META-INF/services/org.junit.jupiter.api.extension.Extension
@@ -1 +1 @@
-org.mockito.junit.jupiter.MockitoExtension
+org.mockito.junit.jupiter.extensions.MockitoExtension
diff --git a/subprojects/junitJupiterParallelTest/src/test/java/org/mockito/NestedParallelTest.java b/subprojects/junitJupiterParallelTest/src/test/java/org/mockito/NestedParallelTest.java
index 29a83467e..e26661a82 100644
--- a/subprojects/junitJupiterParallelTest/src/test/java/org/mockito/NestedParallelTest.java
+++ b/subprojects/junitJupiterParallelTest/src/test/java/org/mockito/NestedParallelTest.java
@@ -7,7 +7,7 @@ package org.mockito;
 import org.junit.jupiter.api.Nested;
 import org.junit.jupiter.api.Test;
 import org.junit.jupiter.api.extension.ExtendWith;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 
 @ExtendWith(MockitoExtension.class)
 class NestedParallelTest {
diff --git a/subprojects/junitJupiterParallelTest/src/test/java/org/mockito/ParallelBugTest.java b/subprojects/junitJupiterParallelTest/src/test/java/org/mockito/ParallelBugTest.java
index e3e1f8bb4..02386b335 100644
--- a/subprojects/junitJupiterParallelTest/src/test/java/org/mockito/ParallelBugTest.java
+++ b/subprojects/junitJupiterParallelTest/src/test/java/org/mockito/ParallelBugTest.java
@@ -6,7 +6,7 @@ package org.mockito;
 
 import org.junit.jupiter.api.Test;
 import org.junit.jupiter.api.extension.ExtendWith;
-import org.mockito.junit.jupiter.MockitoExtension;
+import org.mockito.junit.jupiter.extensions.MockitoExtension;
 
 /**
  * See bug #1630

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

