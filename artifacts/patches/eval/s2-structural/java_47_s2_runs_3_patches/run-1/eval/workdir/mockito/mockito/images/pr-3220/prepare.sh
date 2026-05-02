#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout a0214364c36c840b259a4e5a0b656378e47d90df

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/DoNotMock.java b/src/main/java/org/mockito/DoNotMock.java
index fb2de8ecf..d1e5db0c5 100644
--- a/src/main/java/org/mockito/DoNotMock.java
+++ b/src/main/java/org/mockito/DoNotMock.java
@@ -4,6 +4,8 @@
  */
 package org.mockito;
 
+import org.mockito.configuration.DoNotMockEnforcer;
+
 import static java.lang.annotation.ElementType.TYPE;
 import static java.lang.annotation.RetentionPolicy.RUNTIME;
 
@@ -16,9 +18,9 @@ import java.lang.annotation.Target;
  * <p>When marking a type {@code @DoNotMock}, you should always point to alternative testing
  * solutions such as standard fakes or other testing utilities.
  *
- * Mockito enforces {@code @DoNotMock} with the {@link org.mockito.plugins.DoNotMockEnforcer}.
+ * Mockito enforces {@code @DoNotMock} with the {@link DoNotMockEnforcer}.
  *
- * If you want to use a custom {@code @DoNotMock} annotation, the {@link org.mockito.plugins.DoNotMockEnforcer}
+ * If you want to use a custom {@code @DoNotMock} annotation, the {@link DoNotMockEnforcer}
  * will match on annotations with a type ending in "org.mockito.DoNotMock". You can thus place
  * your custom annotation in {@code com.my.package.org.mockito.DoNotMock} and Mockito will enforce
  * that types annotated by {@code @com.my.package.org.mockito.DoNotMock} can not be mocked.
diff --git a/src/main/java/org/mockito/MockSettings.java b/src/main/java/org/mockito/MockSettings.java
index e9c75c3a1..af899d55c 100644
--- a/src/main/java/org/mockito/MockSettings.java
+++ b/src/main/java/org/mockito/MockSettings.java
@@ -14,7 +14,7 @@ import org.mockito.invocation.MockHandler;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.listeners.StubbingLookupListener;
 import org.mockito.listeners.VerificationStartedListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 import org.mockito.quality.Strictness;
diff --git a/src/main/java/org/mockito/MockingDetails.java b/src/main/java/org/mockito/MockingDetails.java
index 37a149100..190a03bd6 100644
--- a/src/main/java/org/mockito/MockingDetails.java
+++ b/src/main/java/org/mockito/MockingDetails.java
@@ -8,7 +8,7 @@ import java.util.Collection;
 
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.quality.MockitoHint;
 import org.mockito.stubbing.Stubbing;
 
diff --git a/src/main/java/org/mockito/Mockito.java b/src/main/java/org/mockito/Mockito.java
index 75ad37e86..ac70f7b2e 100644
--- a/src/main/java/org/mockito/Mockito.java
+++ b/src/main/java/org/mockito/Mockito.java
@@ -6,7 +6,7 @@ package org.mockito;
 
 import org.mockito.exceptions.misusing.PotentialStubbingProblem;
 import org.mockito.exceptions.misusing.UnnecessaryStubbingException;
-import org.mockito.internal.MockitoCore;
+import org.mockito.internal.framework.MockitoCore;
 import org.mockito.internal.creation.MockSettingsImpl;
 import org.mockito.internal.framework.DefaultMockitoFramework;
 import org.mockito.internal.session.DefaultMockitoSessionBuilder;
diff --git a/src/main/java/org/mockito/plugins/DoNotMockEnforcer.java b/src/main/java/org/mockito/configuration/DoNotMockEnforcer.java
similarity index 96%
rename from src/main/java/org/mockito/plugins/DoNotMockEnforcer.java
rename to src/main/java/org/mockito/configuration/DoNotMockEnforcer.java
index a033bbce5..d946af6cf 100644
--- a/src/main/java/org/mockito/plugins/DoNotMockEnforcer.java
+++ b/src/main/java/org/mockito/configuration/DoNotMockEnforcer.java
@@ -2,7 +2,7 @@
  * Copyright (c) 2019 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.plugins;
+package org.mockito.configuration;
 
 /**
  * Enforcer that is applied to every type in the type hierarchy of the class-to-be-mocked.
diff --git a/src/main/java/org/mockito/mock/MockCreationSettings.java b/src/main/java/org/mockito/configuration/MockCreationSettings.java
similarity index 90%
rename from src/main/java/org/mockito/mock/MockCreationSettings.java
rename to src/main/java/org/mockito/configuration/MockCreationSettings.java
index 949af03b2..be8a4cff0 100644
--- a/src/main/java/org/mockito/mock/MockCreationSettings.java
+++ b/src/main/java/org/mockito/configuration/MockCreationSettings.java
@@ -2,7 +2,7 @@
  * Copyright (c) 2007 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.mock;
+package org.mockito.configuration;
 
 import java.lang.reflect.Type;
 import java.util.List;
@@ -13,6 +13,8 @@ import org.mockito.NotExtensible;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.listeners.StubbingLookupListener;
 import org.mockito.listeners.VerificationStartedListener;
+import org.mockito.mock.MockName;
+import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Answer;
@@ -24,56 +26,52 @@ import org.mockito.stubbing.Answer;
 public interface MockCreationSettings<T> {
 
     /**
-     * Mocked type. An interface or class the mock should implement / extend.
-     */
-    Class<T> getTypeToMock();
-
-    /**
-     * The generic type of the mock, if any.
-     */
-    Type getGenericTypeToMock();
-
-    /**
-     * the extra interfaces the mock object should implement.
-     */
-    Set<Class<?>> getExtraInterfaces();
-
-    /**
-     * the name of this mock, as printed on verification errors; see {@link org.mockito.MockSettings#name}.
+     * Informs whether the mock instance should be created via constructor
+     *
+     * @since 1.10.12
      */
-    MockName getMockName();
+    boolean isUsingConstructor();
 
     /**
-     * the default answer for this mock, see {@link org.mockito.MockSettings#defaultAnswer}.
+     * Whether the mock is only for stubbing, i.e. does not remember
+     * parameters on its invocation and therefore cannot
+     * be used for verification
      */
-    Answer<?> getDefaultAnswer();
+    boolean isStubOnly();
 
     /**
-     * the spied instance - needed for spies.
+     * Whether the mock should not make a best effort to preserve annotations.
      */
-    Object getSpiedInstance();
+    boolean isStripAnnotations();
 
     /**
-     * if the mock is serializable, see {@link org.mockito.MockSettings#serializable}.
+     * if the mock is serializable, see {@link MockSettings#serializable}.
      */
     boolean isSerializable();
 
     /**
-     * @return the serializable mode of this mock
+     *  @deprecated Use {@link MockCreationSettings#getStrictness()} instead.
+     *
+     * Informs if the mock was created with "lenient" strictness, e.g. having {@link Strictness#LENIENT} characteristic.
+     * For more information about using mocks with lenient strictness, see {@link MockSettings#lenient()}.
+     *
+     * @since 2.20.0
      */
-    SerializableMode getSerializableMode();
+    @Deprecated
+    boolean isLenient();
 
     /**
-     * Whether the mock is only for stubbing, i.e. does not remember
-     * parameters on its invocation and therefore cannot
-     * be used for verification
+     * {@link VerificationStartedListener} instances attached to this mock,
+     * see {@link MockSettings#verificationStartedListeners(VerificationStartedListener...)}
+     *
+     * @since 2.11.0
      */
-    boolean isStubOnly();
+    List<VerificationStartedListener> getVerificationStartedListeners();
 
     /**
-     * Whether the mock should not make a best effort to preserve annotations.
+     * Mocked type. An interface or class the mock should implement / extend.
      */
-    boolean isStripAnnotations();
+    Class<T> getTypeToMock();
 
     /**
      * Returns {@link StubbingLookupListener} instances attached to this mock via {@link MockSettings#stubbingLookupListeners(StubbingLookupListener...)}.
@@ -86,35 +84,22 @@ public interface MockCreationSettings<T> {
     List<StubbingLookupListener> getStubbingLookupListeners();
 
     /**
-     * {@link InvocationListener} instances attached to this mock, see {@link org.mockito.MockSettings#invocationListeners(InvocationListener...)}.
-     */
-    List<InvocationListener> getInvocationListeners();
-
-    /**
-     * {@link VerificationStartedListener} instances attached to this mock,
-     * see {@link org.mockito.MockSettings#verificationStartedListeners(VerificationStartedListener...)}
+     * Sets strictness level for the mock, e.g. having {@link Strictness#STRICT_STUBS} characteristic.
+     * For more information about using mocks with custom strictness, see {@link MockSettings#strictness(Strictness)}.
      *
-     * @since 2.11.0
+     * @since 4.6.0
      */
-    List<VerificationStartedListener> getVerificationStartedListeners();
+    Strictness getStrictness();
 
     /**
-     * Informs whether the mock instance should be created via constructor
-     *
-     * @since 1.10.12
+     * the spied instance - needed for spies.
      */
-    boolean isUsingConstructor();
+    Object getSpiedInstance();
 
     /**
-     * Used when arguments should be passed to the mocked object's constructor, regardless of whether these
-     * arguments are supplied directly, or whether they include the outer instance.
-     *
-     * @return An array of arguments that are passed to the mocked object's constructor. If
-     * {@link #getOuterClassInstance()} is available, it is prepended to the passed arguments.
-     *
-     * @since 2.7.14
+     * @return the serializable mode of this mock
      */
-    Object[] getConstructorArgs();
+    SerializableMode getSerializableMode();
 
     /**
      * Used when mocking non-static inner classes in conjunction with {@link #isUsingConstructor()}
@@ -125,23 +110,9 @@ public interface MockCreationSettings<T> {
     Object getOuterClassInstance();
 
     /**
-     *  @deprecated Use {@link MockCreationSettings#getStrictness()} instead.
-     *
-     * Informs if the mock was created with "lenient" strictness, e.g. having {@link Strictness#LENIENT} characteristic.
-     * For more information about using mocks with lenient strictness, see {@link MockSettings#lenient()}.
-     *
-     * @since 2.20.0
-     */
-    @Deprecated
-    boolean isLenient();
-
-    /**
-     * Sets strictness level for the mock, e.g. having {@link Strictness#STRICT_STUBS} characteristic.
-     * For more information about using mocks with custom strictness, see {@link MockSettings#strictness(Strictness)}.
-     *
-     * @since 4.6.0
+     * the name of this mock, as printed on verification errors; see {@link MockSettings#name}.
      */
-    Strictness getStrictness();
+    MockName getMockName();
 
     /**
      * Returns the {@link MockMaker} which shall be used to create the mock.
@@ -151,4 +122,35 @@ public interface MockCreationSettings<T> {
      * @since 4.8.0
      */
     String getMockMaker();
+
+    /**
+     * {@link InvocationListener} instances attached to this mock, see {@link MockSettings#invocationListeners(InvocationListener...)}.
+     */
+    List<InvocationListener> getInvocationListeners();
+
+    /**
+     * The generic type of the mock, if any.
+     */
+    Type getGenericTypeToMock();
+
+    /**
+     * the extra interfaces the mock object should implement.
+     */
+    Set<Class<?>> getExtraInterfaces();
+
+    /**
+     * the default answer for this mock, see {@link MockSettings#defaultAnswer}.
+     */
+    Answer<?> getDefaultAnswer();
+
+    /**
+     * Used when arguments should be passed to the mocked object's constructor, regardless of whether these
+     * arguments are supplied directly, or whether they include the outer instance.
+     *
+     * @return An array of arguments that are passed to the mocked object's constructor. If
+     * {@link #getOuterClassInstance()} is available, it is prepended to the passed arguments.
+     *
+     * @since 2.7.14
+     */
+    Object[] getConstructorArgs();
 }
diff --git a/src/main/java/org/mockito/internal/InOrderImpl.java b/src/main/java/org/mockito/internal/InOrderImpl.java
index 93f5991af..64fc07653 100644
--- a/src/main/java/org/mockito/internal/InOrderImpl.java
+++ b/src/main/java/org/mockito/internal/InOrderImpl.java
@@ -13,6 +13,7 @@ import org.mockito.InOrder;
 import org.mockito.MockedStatic;
 import org.mockito.MockingDetails;
 import org.mockito.exceptions.base.MockitoException;
+import org.mockito.internal.framework.MockitoCore;
 import org.mockito.internal.verification.InOrderContextImpl;
 import org.mockito.internal.verification.InOrderWrapper;
 import org.mockito.internal.verification.VerificationModeFactory;
diff --git a/src/main/java/org/mockito/internal/configuration/DefaultDoNotMockEnforcer.java b/src/main/java/org/mockito/internal/configuration/DefaultDoNotMockEnforcer.java
index ada97d656..5fb1eb33a 100644
--- a/src/main/java/org/mockito/internal/configuration/DefaultDoNotMockEnforcer.java
+++ b/src/main/java/org/mockito/internal/configuration/DefaultDoNotMockEnforcer.java
@@ -7,7 +7,7 @@ package org.mockito.internal.configuration;
 import java.lang.annotation.Annotation;
 
 import org.mockito.DoNotMock;
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.configuration.DoNotMockEnforcer;
 
 public class DefaultDoNotMockEnforcer implements DoNotMockEnforcer {
 
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java b/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
index c7644257f..47b80020d 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
@@ -12,7 +12,7 @@ import java.util.Set;
 import org.mockito.MockMakers;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.plugins.AnnotationEngine;
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.configuration.DoNotMockEnforcer;
 import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
@@ -74,15 +74,25 @@ public class DefaultMockitoPlugins implements MockitoPlugins {
     }
 
     @Override
-    public <T> T getDefaultPlugin(Class<T> pluginType) {
-        String className = DEFAULT_PLUGINS.get(pluginType.getName());
-        return create(pluginType, className);
+    public MockMaker getMockMaker(String mockMaker) {
+        return MockUtil.getMockMaker(mockMaker);
+    }
+
+    @Override
+    public MockMaker getInlineMockMaker() {
+        return create(MockMaker.class, DEFAULT_PLUGINS.get(INLINE_ALIAS));
     }
 
     public static String getDefaultPluginClass(String classOrAlias) {
         return DEFAULT_PLUGINS.get(classOrAlias);
     }
 
+    @Override
+    public <T> T getDefaultPlugin(Class<T> pluginType) {
+        String className = DEFAULT_PLUGINS.get(pluginType.getName());
+        return create(pluginType, className);
+    }
+
     /**
      * Creates an instance of given plugin type, using specific implementation class.
      */
@@ -110,14 +120,4 @@ public class DefaultMockitoPlugins implements MockitoPlugins {
                     e);
         }
     }
-
-    @Override
-    public MockMaker getInlineMockMaker() {
-        return create(MockMaker.class, DEFAULT_PLUGINS.get(INLINE_ALIAS));
-    }
-
-    @Override
-    public MockMaker getMockMaker(String mockMaker) {
-        return MockUtil.getMockMaker(mockMaker);
-    }
 }
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java b/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java
index 72f5d8e7d..25fcb7667 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java
@@ -6,7 +6,7 @@ package org.mockito.internal.configuration.plugins;
 
 import java.util.List;
 import org.mockito.plugins.AnnotationEngine;
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.configuration.DoNotMockEnforcer;
 import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
@@ -49,11 +49,6 @@ class PluginRegistry {
     private final DoNotMockEnforcer doNotMockEnforcer =
             new PluginLoader(pluginSwitch).loadPlugin(DoNotMockEnforcer.class);
 
-    PluginRegistry() {
-        instantiatorProvider =
-                new PluginLoader(pluginSwitch).loadPlugin(InstantiatorProvider2.class);
-    }
-
     /**
      * The implementation of the stack trace cleaner
      */
@@ -62,11 +57,30 @@ class PluginRegistry {
         return stackTraceCleanerProvider;
     }
 
+    /**
+     * Returns the logger available for the current runtime.
+     *
+     * <p>Returns {@link org.mockito.internal.util.ConsoleMockitoLogger} if no
+     * {@link MockitoLogger} extension exists or is visible in the current classpath.</p>
+     */
+    MockitoLogger getMockitoLogger() {
+        return mockitoLogger;
+    }
+
+    /**
+     * Returns a list of available mock resolvers if any.
+     *
+     * @return A list of available mock resolvers or an empty list if none are registered.
+     */
+    List<MockResolver> getMockResolvers() {
+        return mockResolvers;
+    }
+
     /**
      * Returns the implementation of the mock maker available for the current runtime.
      *
      * <p>Returns {@link org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker} if no
-     * {@link org.mockito.plugins.MockMaker} extension exists or is visible in the current classpath.</p>
+     * {@link MockMaker} extension exists or is visible in the current classpath.</p>
      */
     MockMaker getMockMaker() {
         return mockMaker;
@@ -76,7 +90,7 @@ class PluginRegistry {
      * Returns the implementation of the member accessor available for the current runtime.
      *
      * <p>Returns {@link org.mockito.internal.util.reflection.ReflectionMemberAccessor} if no
-     * {@link org.mockito.plugins.MockMaker} extension exists or is visible in the current classpath.</p>
+     * {@link MockMaker} extension exists or is visible in the current classpath.</p>
      */
     MemberAccessor getMemberAccessor() {
         return memberAccessor;
@@ -86,33 +100,13 @@ class PluginRegistry {
      * Returns the instantiator provider available for the current runtime.
      *
      * <p>Returns {@link org.mockito.internal.creation.instance.DefaultInstantiatorProvider} if no
-     * {@link org.mockito.plugins.InstantiatorProvider2} extension exists or is visible in the
+     * {@link InstantiatorProvider2} extension exists or is visible in the
      * current classpath.</p>
      */
     InstantiatorProvider2 getInstantiatorProvider() {
         return instantiatorProvider;
     }
 
-    /**
-     * Returns the annotation engine available for the current runtime.
-     *
-     * <p>Returns {@link org.mockito.internal.configuration.InjectingAnnotationEngine} if no
-     * {@link org.mockito.plugins.AnnotationEngine} extension exists or is visible in the current classpath.</p>
-     */
-    AnnotationEngine getAnnotationEngine() {
-        return annotationEngine;
-    }
-
-    /**
-     * Returns the logger available for the current runtime.
-     *
-     * <p>Returns {@link org.mockito.internal.util.ConsoleMockitoLogger} if no
-     * {@link org.mockito.plugins.MockitoLogger} extension exists or is visible in the current classpath.</p>
-     */
-    MockitoLogger getMockitoLogger() {
-        return mockitoLogger;
-    }
-
     /**
      * Returns the DoNotMock enforce for the current runtime.
      *
@@ -124,11 +118,17 @@ class PluginRegistry {
     }
 
     /**
-     * Returns a list of available mock resolvers if any.
+     * Returns the annotation engine available for the current runtime.
      *
-     * @return A list of available mock resolvers or an empty list if none are registered.
+     * <p>Returns {@link org.mockito.internal.configuration.InjectingAnnotationEngine} if no
+     * {@link AnnotationEngine} extension exists or is visible in the current classpath.</p>
      */
-    List<MockResolver> getMockResolvers() {
-        return mockResolvers;
+    AnnotationEngine getAnnotationEngine() {
+        return annotationEngine;
+    }
+
+    PluginRegistry() {
+        instantiatorProvider =
+                new PluginLoader(pluginSwitch).loadPlugin(InstantiatorProvider2.class);
     }
 }
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java b/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
index 20f6dc7bc..db95ab1dd 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
@@ -7,7 +7,7 @@ package org.mockito.internal.configuration.plugins;
 import org.mockito.DoNotMock;
 import java.util.List;
 import org.mockito.plugins.AnnotationEngine;
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.configuration.DoNotMockEnforcer;
 import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
@@ -29,70 +29,60 @@ public final class Plugins {
     }
 
     /**
-     * Returns the implementation of the mock maker available for the current runtime.
-     *
-     * <p>Returns default mock maker if no
-     * {@link org.mockito.plugins.MockMaker} extension exists or is visible in the current classpath.</p>
+     * @return instance of mockito plugins type
      */
-    public static MockMaker getMockMaker() {
-        return registry.getMockMaker();
+    public static MockitoPlugins getPlugins() {
+        return new DefaultMockitoPlugins();
     }
 
     /**
-     * Returns the implementation of the member accessor available for the current runtime.
+     * Returns the logger available for the current runtime.
      *
-     * <p>Returns default member accessor if no
-     * {@link org.mockito.plugins.MemberAccessor} extension exists or is visible in the current classpath.</p>
+     * <p>Returns {@link org.mockito.internal.util.ConsoleMockitoLogger} if no
+     * {@link MockitoLogger} extension exists or is visible in the current classpath.</p>
      */
-    public static MemberAccessor getMemberAccessor() {
-        return registry.getMemberAccessor();
+    public static MockitoLogger getMockitoLogger() {
+        return registry.getMockitoLogger();
     }
 
     /**
-     * Returns the instantiator provider available for the current runtime.
+     * Returns a list of available mock resolvers if any.
      *
-     * <p>Returns {@link org.mockito.internal.creation.instance.DefaultInstantiatorProvider} if no
-     * {@link org.mockito.plugins.InstantiatorProvider2} extension exists or is visible in the
-     * current classpath.</p>
+     * @return A list of available mock resolvers or an empty list if none are registered.
      */
-    public static InstantiatorProvider2 getInstantiatorProvider() {
-        return registry.getInstantiatorProvider();
+    public static List<MockResolver> getMockResolvers() {
+        return registry.getMockResolvers();
     }
 
     /**
-     * Returns the annotation engine available for the current runtime.
+     * Returns the implementation of the mock maker available for the current runtime.
      *
-     * <p>Returns {@link org.mockito.internal.configuration.InjectingAnnotationEngine} if no
-     * {@link org.mockito.plugins.AnnotationEngine} extension exists or is visible in the current classpath.</p>
+     * <p>Returns default mock maker if no
+     * {@link MockMaker} extension exists or is visible in the current classpath.</p>
      */
-    public static AnnotationEngine getAnnotationEngine() {
-        return registry.getAnnotationEngine();
+    public static MockMaker getMockMaker() {
+        return registry.getMockMaker();
     }
 
     /**
-     * Returns the logger available for the current runtime.
+     * Returns the implementation of the member accessor available for the current runtime.
      *
-     * <p>Returns {@link org.mockito.internal.util.ConsoleMockitoLogger} if no
-     * {@link org.mockito.plugins.MockitoLogger} extension exists or is visible in the current classpath.</p>
+     * <p>Returns default member accessor if no
+     * {@link MemberAccessor} extension exists or is visible in the current classpath.</p>
      */
-    public static MockitoLogger getMockitoLogger() {
-        return registry.getMockitoLogger();
+    public static MemberAccessor getMemberAccessor() {
+        return registry.getMemberAccessor();
     }
 
     /**
-     * Returns a list of available mock resolvers if any.
+     * Returns the instantiator provider available for the current runtime.
      *
-     * @return A list of available mock resolvers or an empty list if none are registered.
-     */
-    public static List<MockResolver> getMockResolvers() {
-        return registry.getMockResolvers();
-    }
-
-    /**
-     * @return instance of mockito plugins type
+     * <p>Returns {@link org.mockito.internal.creation.instance.DefaultInstantiatorProvider} if no
+     * {@link InstantiatorProvider2} extension exists or is visible in the
+     * current classpath.</p>
      */
-    public static MockitoPlugins getPlugins() {
-        return new DefaultMockitoPlugins();
+    public static InstantiatorProvider2 getInstantiatorProvider() {
+        return registry.getInstantiatorProvider();
     }
 
     /**
@@ -105,5 +95,15 @@ public final class Plugins {
         return registry.getDoNotMockEnforcer();
     }
 
+    /**
+     * Returns the annotation engine available for the current runtime.
+     *
+     * <p>Returns {@link org.mockito.internal.configuration.InjectingAnnotationEngine} if no
+     * {@link AnnotationEngine} extension exists or is visible in the current classpath.</p>
+     */
+    public static AnnotationEngine getAnnotationEngine() {
+        return registry.getAnnotationEngine();
+    }
+
     private Plugins() {}
 }
diff --git a/src/main/java/org/mockito/internal/creation/MockSettingsImpl.java b/src/main/java/org/mockito/internal/creation/MockSettingsImpl.java
index 7bef7764d..1f910c7a5 100644
--- a/src/main/java/org/mockito/internal/creation/MockSettingsImpl.java
+++ b/src/main/java/org/mockito/internal/creation/MockSettingsImpl.java
@@ -28,11 +28,11 @@ import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.debugging.VerboseMockInvocationLogger;
 import org.mockito.internal.util.Checks;
 import org.mockito.internal.util.MockCreationValidator;
-import org.mockito.internal.util.MockNameImpl;
+import org.mockito.mock.MockNameImpl;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.listeners.StubbingLookupListener;
 import org.mockito.listeners.VerificationStartedListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.mock.MockName;
 import org.mockito.mock.SerializableMode;
 import org.mockito.quality.Strictness;
@@ -48,78 +48,68 @@ public class MockSettingsImpl<T> extends CreationSettings<T>
     private Object[] constructorArgs;
 
     @Override
-    public MockSettings serializable() {
-        return serializable(SerializableMode.BASIC);
+    public MockSettings withoutAnnotations() {
+        stripAnnotations = true;
+        return this;
     }
 
     @Override
-    public MockSettings serializable(SerializableMode mode) {
-        this.serializableMode = mode;
+    public MockSettings verificationStartedListeners(VerificationStartedListener... listeners) {
+        addListeners(listeners, this.verificationStartedListeners, "verificationStartedListeners");
         return this;
     }
 
     @Override
-    public MockSettings extraInterfaces(Class<?>... extraInterfaces) {
-        if (extraInterfaces == null || extraInterfaces.length == 0) {
-            throw extraInterfacesRequiresAtLeastOneInterface();
-        }
-
-        for (Class<?> i : extraInterfaces) {
-            if (i == null) {
-                throw extraInterfacesDoesNotAcceptNullParameters();
-            } else if (!i.isInterface()) {
-                throw extraInterfacesAcceptsOnlyInterfaces(i);
-            }
+    public MockSettings verboseLogging() {
+        if (!invocationListenersContainsType(VerboseMockInvocationLogger.class)) {
+            invocationListeners(new VerboseMockInvocationLogger());
         }
-        this.extraInterfaces = newSet(extraInterfaces);
         return this;
     }
 
-    @Override
-    public MockName getMockName() {
-        return mockName;
-    }
+    private static <T> CreationSettings<T> validatedStaticSettings(
+            Class<T> classToMock, CreationSettings<T> source) {
 
-    @Override
-    public Set<Class<?>> getExtraInterfaces() {
-        return extraInterfaces;
-    }
+        if (classToMock.isPrimitive()) {
+            throw new MockitoException(
+                    "Cannot create static mock of primitive type " + classToMock);
+        }
+        if (!source.getExtraInterfaces().isEmpty()) {
+            throw new MockitoException(
+                    "Cannot specify additional interfaces for static mock of " + classToMock);
+        }
+        if (source.getSpiedInstance() != null) {
+            throw new MockitoException(
+                    "Cannot specify spied instance for static mock of " + classToMock);
+        }
 
-    @Override
-    public Object getSpiedInstance() {
-        return spiedInstance;
+        CreationSettings<T> settings = new CreationSettings<T>(source);
+        settings.setMockName(new MockNameImpl(source.getName(), classToMock, true));
+        settings.setTypeToMock(classToMock);
+        return settings;
     }
 
-    @Override
-    public MockSettings name(String name) {
-        this.name = name;
-        return this;
-    }
+    private static <T> CreationSettings<T> validatedSettings(
+            Class<T> typeToMock, CreationSettings<T> source) {
+        MockCreationValidator validator = new MockCreationValidator();
 
-    @Override
-    public MockSettings spiedInstance(Object spiedInstance) {
-        this.spiedInstance = spiedInstance;
-        return this;
-    }
+        validator.validateType(typeToMock, source.getMockMaker());
+        validator.validateExtraInterfaces(typeToMock, source.getExtraInterfaces());
+        validator.validateMockedType(typeToMock, source.getSpiedInstance());
 
-    @Override
-    public MockSettings defaultAnswer(Answer defaultAnswer) {
-        this.defaultAnswer = defaultAnswer;
-        if (defaultAnswer == null) {
-            throw defaultAnswerDoesNotAcceptNullParameter();
-        }
-        return this;
-    }
+        // TODO SF - add this validation and also add missing coverage
+        //        validator.validateDelegatedInstance(classToMock, settings.getDelegatedInstance());
 
-    @Override
-    public Answer<Object> getDefaultAnswer() {
-        return defaultAnswer;
-    }
+        validator.validateConstructorUse(source.isUsingConstructor(), source.getSerializableMode());
 
-    @Override
-    public MockSettingsImpl<T> stubOnly() {
-        this.stubOnly = true;
-        return this;
+        // TODO SF - I don't think we really need CreationSettings type
+        // TODO do we really need to copy the entire settings every time we create mock object? it
+        // does not seem necessary.
+        CreationSettings<T> settings = new CreationSettings<T>(source);
+        settings.setMockName(new MockNameImpl(source.getName(), typeToMock, false));
+        settings.setTypeToMock(typeToMock);
+        settings.setExtraInterfaces(prepareExtraInterfaces(source));
+        return settings;
     }
 
     @Override
@@ -134,82 +124,83 @@ public class MockSettingsImpl<T> extends CreationSettings<T>
     }
 
     @Override
-    public MockSettings outerInstance(Object outerClassInstance) {
-        this.outerClassInstance = outerClassInstance;
+    public MockSettings stubbingLookupListeners(StubbingLookupListener... listeners) {
+        addListeners(listeners, stubbingLookupListeners, "stubbingLookupListeners");
         return this;
     }
 
     @Override
-    public MockSettings withoutAnnotations() {
-        stripAnnotations = true;
+    public MockSettingsImpl<T> stubOnly() {
+        this.stubOnly = true;
         return this;
     }
 
     @Override
-    public boolean isUsingConstructor() {
-        return useConstructor;
+    public MockSettings strictness(Strictness strictness) {
+        if (strictness == null) {
+            throw strictnessDoesNotAcceptNullParameter();
+        }
+        this.strictness = strictness;
+        return this;
     }
 
     @Override
-    public Object getOuterClassInstance() {
-        return outerClassInstance;
+    public MockSettings spiedInstance(Object spiedInstance) {
+        this.spiedInstance = spiedInstance;
+        return this;
     }
 
     @Override
-    public Object[] getConstructorArgs() {
-        if (outerClassInstance == null) {
-            return constructorArgs;
+    public MockSettings serializable() {
+        return serializable(SerializableMode.BASIC);
+    }
+
+    @Override
+    public MockSettings serializable(SerializableMode mode) {
+        this.serializableMode = mode;
+        return this;
+    }
+
+    private static Set<Class<?>> prepareExtraInterfaces(CreationSettings settings) {
+        Set<Class<?>> interfaces = new HashSet<>(settings.getExtraInterfaces());
+        if (settings.isSerializable()) {
+            interfaces.add(Serializable.class);
         }
-        List<Object> resultArgs = new ArrayList<>(constructorArgs.length + 1);
-        resultArgs.add(outerClassInstance);
-        resultArgs.addAll(asList(constructorArgs));
-        return resultArgs.toArray(new Object[constructorArgs.length + 1]);
+        return interfaces;
     }
 
     @Override
-    public boolean isStubOnly() {
-        return this.stubOnly;
+    public MockSettings outerInstance(Object outerClassInstance) {
+        this.outerClassInstance = outerClassInstance;
+        return this;
     }
 
     @Override
-    public MockSettings verboseLogging() {
-        if (!invocationListenersContainsType(VerboseMockInvocationLogger.class)) {
-            invocationListeners(new VerboseMockInvocationLogger());
-        }
+    public MockSettings name(String name) {
+        this.name = name;
         return this;
     }
 
     @Override
-    public MockSettings invocationListeners(InvocationListener... listeners) {
-        addListeners(listeners, invocationListeners, "invocationListeners");
+    public MockSettings mockMaker(String mockMaker) {
+        this.mockMaker = mockMaker;
         return this;
     }
 
     @Override
-    public MockSettings stubbingLookupListeners(StubbingLookupListener... listeners) {
-        addListeners(listeners, stubbingLookupListeners, "stubbingLookupListeners");
+    public MockSettings lenient() {
+        this.strictness = Strictness.LENIENT;
         return this;
     }
 
-    static <T> void addListeners(T[] listeners, List<T> container, String method) {
-        if (listeners == null) {
-            throw methodDoesNotAcceptParameter(method, "null vararg array.");
-        }
-        if (listeners.length == 0) {
-            throw requiresAtLeastOneListener(method);
-        }
-        for (T listener : listeners) {
-            if (listener == null) {
-                throw methodDoesNotAcceptParameter(method, "null listeners.");
-            }
-            container.add(listener);
-        }
+    @Override
+    public boolean isUsingConstructor() {
+        return useConstructor;
     }
 
     @Override
-    public MockSettings verificationStartedListeners(VerificationStartedListener... listeners) {
-        addListeners(listeners, this.verificationStartedListeners, "verificationStartedListeners");
-        return this;
+    public boolean isStubOnly() {
+        return this.stubOnly;
     }
 
     private boolean invocationListenersContainsType(Class<?> clazz) {
@@ -221,6 +212,12 @@ public class MockSettingsImpl<T> extends CreationSettings<T>
         return false;
     }
 
+    @Override
+    public MockSettings invocationListeners(InvocationListener... listeners) {
+        addListeners(listeners, invocationListeners, "invocationListeners");
+        return this;
+    }
+
     public boolean hasInvocationListeners() {
         return !getInvocationListeners().isEmpty();
     }
@@ -231,34 +228,39 @@ public class MockSettingsImpl<T> extends CreationSettings<T>
     }
 
     @Override
-    public <T2> MockCreationSettings<T2> build(Class<T2> typeToMock) {
-        return validatedSettings(typeToMock, (CreationSettings<T2>) this);
+    public Object getSpiedInstance() {
+        return spiedInstance;
     }
 
     @Override
-    public <T2> MockCreationSettings<T2> buildStatic(Class<T2> classToMock) {
-        return validatedStaticSettings(classToMock, (CreationSettings<T2>) this);
+    public Object getOuterClassInstance() {
+        return outerClassInstance;
     }
 
     @Override
-    public MockSettings lenient() {
-        this.strictness = Strictness.LENIENT;
-        return this;
+    public MockName getMockName() {
+        return mockName;
     }
 
     @Override
-    public MockSettings strictness(Strictness strictness) {
-        if (strictness == null) {
-            throw strictnessDoesNotAcceptNullParameter();
-        }
-        this.strictness = strictness;
-        return this;
+    public Set<Class<?>> getExtraInterfaces() {
+        return extraInterfaces;
     }
 
     @Override
-    public MockSettings mockMaker(String mockMaker) {
-        this.mockMaker = mockMaker;
-        return this;
+    public Answer<Object> getDefaultAnswer() {
+        return defaultAnswer;
+    }
+
+    @Override
+    public Object[] getConstructorArgs() {
+        if (outerClassInstance == null) {
+            return constructorArgs;
+        }
+        List<Object> resultArgs = new ArrayList<>(constructorArgs.length + 1);
+        resultArgs.add(outerClassInstance);
+        resultArgs.addAll(asList(constructorArgs));
+        return resultArgs.toArray(new Object[constructorArgs.length + 1]);
     }
 
     @Override
@@ -267,56 +269,54 @@ public class MockSettingsImpl<T> extends CreationSettings<T>
         return this;
     }
 
-    private static <T> CreationSettings<T> validatedSettings(
-            Class<T> typeToMock, CreationSettings<T> source) {
-        MockCreationValidator validator = new MockCreationValidator();
-
-        validator.validateType(typeToMock, source.getMockMaker());
-        validator.validateExtraInterfaces(typeToMock, source.getExtraInterfaces());
-        validator.validateMockedType(typeToMock, source.getSpiedInstance());
+    @Override
+    public MockSettings extraInterfaces(Class<?>... extraInterfaces) {
+        if (extraInterfaces == null || extraInterfaces.length == 0) {
+            throw extraInterfacesRequiresAtLeastOneInterface();
+        }
 
-        // TODO SF - add this validation and also add missing coverage
-        //        validator.validateDelegatedInstance(classToMock, settings.getDelegatedInstance());
+        for (Class<?> i : extraInterfaces) {
+            if (i == null) {
+                throw extraInterfacesDoesNotAcceptNullParameters();
+            } else if (!i.isInterface()) {
+                throw extraInterfacesAcceptsOnlyInterfaces(i);
+            }
+        }
+        this.extraInterfaces = newSet(extraInterfaces);
+        return this;
+    }
 
-        validator.validateConstructorUse(source.isUsingConstructor(), source.getSerializableMode());
+    @Override
+    public MockSettings defaultAnswer(Answer defaultAnswer) {
+        this.defaultAnswer = defaultAnswer;
+        if (defaultAnswer == null) {
+            throw defaultAnswerDoesNotAcceptNullParameter();
+        }
+        return this;
+    }
 
-        // TODO SF - I don't think we really need CreationSettings type
-        // TODO do we really need to copy the entire settings every time we create mock object? it
-        // does not seem necessary.
-        CreationSettings<T> settings = new CreationSettings<T>(source);
-        settings.setMockName(new MockNameImpl(source.getName(), typeToMock, false));
-        settings.setTypeToMock(typeToMock);
-        settings.setExtraInterfaces(prepareExtraInterfaces(source));
-        return settings;
+    @Override
+    public <T2> MockCreationSettings<T2> buildStatic(Class<T2> classToMock) {
+        return validatedStaticSettings(classToMock, (CreationSettings<T2>) this);
     }
 
-    private static <T> CreationSettings<T> validatedStaticSettings(
-            Class<T> classToMock, CreationSettings<T> source) {
+    @Override
+    public <T2> MockCreationSettings<T2> build(Class<T2> typeToMock) {
+        return validatedSettings(typeToMock, (CreationSettings<T2>) this);
+    }
 
-        if (classToMock.isPrimitive()) {
-            throw new MockitoException(
-                    "Cannot create static mock of primitive type " + classToMock);
-        }
-        if (!source.getExtraInterfaces().isEmpty()) {
-            throw new MockitoException(
-                    "Cannot specify additional interfaces for static mock of " + classToMock);
+    static <T> void addListeners(T[] listeners, List<T> container, String method) {
+        if (listeners == null) {
+            throw methodDoesNotAcceptParameter(method, "null vararg array.");
         }
-        if (source.getSpiedInstance() != null) {
-            throw new MockitoException(
-                    "Cannot specify spied instance for static mock of " + classToMock);
+        if (listeners.length == 0) {
+            throw requiresAtLeastOneListener(method);
         }
-
-        CreationSettings<T> settings = new CreationSettings<T>(source);
-        settings.setMockName(new MockNameImpl(source.getName(), classToMock, true));
-        settings.setTypeToMock(classToMock);
-        return settings;
-    }
-
-    private static Set<Class<?>> prepareExtraInterfaces(CreationSettings settings) {
-        Set<Class<?>> interfaces = new HashSet<>(settings.getExtraInterfaces());
-        if (settings.isSerializable()) {
-            interfaces.add(Serializable.class);
+        for (T listener : listeners) {
+            if (listener == null) {
+                throw methodDoesNotAcceptParameter(method, "null listeners.");
+            }
+            container.add(listener);
         }
-        return interfaces;
     }
 }
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
index a1eed21e7..e3d050d8a 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
@@ -25,7 +25,7 @@ import org.mockito.exceptions.base.MockitoSerializationIssue;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.util.MockUtil;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.mock.MockName;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MemberAccessor;
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMaker.java
index 9a836bbbb..47b14cb49 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMaker.java
@@ -7,7 +7,7 @@ package org.mockito.internal.creation.bytebuddy;
 import org.mockito.MockedConstruction;
 import org.mockito.internal.exceptions.Reporter;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 import java.util.Optional;
 import java.util.function.Function;
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/ClassCreatingMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ClassCreatingMockMaker.java
index b6f9b3f89..64fbb5768 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/ClassCreatingMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ClassCreatingMockMaker.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.creation.bytebuddy;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.MockMaker;
 
 interface ClassCreatingMockMaker extends MockMaker {
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..757016b7a 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -8,7 +8,7 @@ import org.mockito.MockedConstruction;
 import org.mockito.creation.instance.Instantiator;
 import org.mockito.internal.exceptions.Reporter;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.InlineMockMaker;
 
 import java.util.Optional;
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
index e03d11b9e..59edd29c6 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
@@ -18,7 +18,7 @@ import org.mockito.internal.util.Platform;
 import org.mockito.internal.util.concurrent.DetachedThreadLocal;
 import org.mockito.internal.util.concurrent.WeakConcurrentMap;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.InlineMockMaker;
 import org.mockito.plugins.MemberAccessor;
 
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodInterceptor.java b/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodInterceptor.java
index 406dea39a..7bad29b57 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodInterceptor.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodInterceptor.java
@@ -26,7 +26,7 @@ import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.invocation.RealMethod;
 import org.mockito.invocation.Location;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 public class MockMethodInterceptor implements Serializable {
 
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMaker.java
index 6bb74322b..a2d8300a4 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMaker.java
@@ -13,7 +13,7 @@ import org.mockito.exceptions.base.MockitoException;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.util.Platform;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * Subclass based mock maker.
diff --git a/src/main/java/org/mockito/internal/creation/instance/DefaultInstantiatorProvider.java b/src/main/java/org/mockito/internal/creation/instance/DefaultInstantiatorProvider.java
index af071bfb3..746e32044 100644
--- a/src/main/java/org/mockito/internal/creation/instance/DefaultInstantiatorProvider.java
+++ b/src/main/java/org/mockito/internal/creation/instance/DefaultInstantiatorProvider.java
@@ -5,7 +5,7 @@
 package org.mockito.internal.creation.instance;
 
 import org.mockito.creation.instance.Instantiator;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.InstantiatorProvider2;
 
 public class DefaultInstantiatorProvider implements InstantiatorProvider2 {
diff --git a/src/main/java/org/mockito/internal/creation/proxy/ProxyMockMaker.java b/src/main/java/org/mockito/internal/creation/proxy/ProxyMockMaker.java
index 88e688611..acb3cbcdd 100644
--- a/src/main/java/org/mockito/internal/creation/proxy/ProxyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/proxy/ProxyMockMaker.java
@@ -9,7 +9,7 @@ import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.invocation.RealMethod;
 import org.mockito.internal.util.Platform;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.MockMaker;
 
 import java.lang.reflect.InvocationHandler;
diff --git a/src/main/java/org/mockito/internal/creation/settings/CreationSettings.java b/src/main/java/org/mockito/internal/creation/settings/CreationSettings.java
index 51544fb9e..68e2c532a 100644
--- a/src/main/java/org/mockito/internal/creation/settings/CreationSettings.java
+++ b/src/main/java/org/mockito/internal/creation/settings/CreationSettings.java
@@ -16,7 +16,7 @@ import java.util.concurrent.CopyOnWriteArrayList;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.listeners.StubbingLookupListener;
 import org.mockito.listeners.VerificationStartedListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.mock.MockName;
 import org.mockito.mock.SerializableMode;
 import org.mockito.quality.Strictness;
@@ -50,38 +50,18 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
     protected Strictness strictness = null;
     protected String mockMaker;
 
-    public CreationSettings() {}
-
-    @SuppressWarnings("unchecked")
-    public CreationSettings(CreationSettings copy) {
-        // TODO can we have a reflection test here? We had a couple of bugs here in the past.
-        this.typeToMock = copy.typeToMock;
-        this.genericTypeToMock = copy.genericTypeToMock;
-        this.extraInterfaces = copy.extraInterfaces;
-        this.name = copy.name;
-        this.spiedInstance = copy.spiedInstance;
-        this.defaultAnswer = copy.defaultAnswer;
-        this.mockName = copy.mockName;
-        this.serializableMode = copy.serializableMode;
-        this.invocationListeners = copy.invocationListeners;
-        this.stubbingLookupListeners = copy.stubbingLookupListeners;
-        this.verificationStartedListeners = copy.verificationStartedListeners;
-        this.stubOnly = copy.stubOnly;
-        this.useConstructor = copy.isUsingConstructor();
-        this.outerClassInstance = copy.getOuterClassInstance();
-        this.constructorArgs = copy.getConstructorArgs();
-        this.strictness = copy.strictness;
-        this.stripAnnotations = copy.stripAnnotations;
-        this.mockMaker = copy.mockMaker;
+    public CreationSettings<T> setTypeToMock(Class<T> typeToMock) {
+        this.typeToMock = typeToMock;
+        return this;
     }
 
-    @Override
-    public Class<T> getTypeToMock() {
-        return typeToMock;
+    public CreationSettings<T> setSerializableMode(SerializableMode serializableMode) {
+        this.serializableMode = serializableMode;
+        return this;
     }
 
-    public CreationSettings<T> setTypeToMock(Class<T> typeToMock) {
-        this.typeToMock = typeToMock;
+    public CreationSettings<T> setMockName(MockName mockName) {
+        this.mockName = mockName;
         return this;
     }
 
@@ -90,38 +70,24 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
         return this;
     }
 
-    @Override
-    public Set<Class<?>> getExtraInterfaces() {
-        return extraInterfaces;
-    }
-
     public CreationSettings<T> setExtraInterfaces(Set<Class<?>> extraInterfaces) {
         this.extraInterfaces = extraInterfaces;
         return this;
     }
 
-    public String getName() {
-        return name;
-    }
-
     @Override
-    public Object getSpiedInstance() {
-        return spiedInstance;
+    public boolean isUsingConstructor() {
+        return useConstructor;
     }
 
     @Override
-    public Answer<Object> getDefaultAnswer() {
-        return defaultAnswer;
+    public boolean isStubOnly() {
+        return stubOnly;
     }
 
     @Override
-    public MockName getMockName() {
-        return mockName;
-    }
-
-    public CreationSettings<T> setMockName(MockName mockName) {
-        this.mockName = mockName;
-        return this;
+    public boolean isStripAnnotations() {
+        return stripAnnotations;
     }
 
     @Override
@@ -129,24 +95,19 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
         return serializableMode != SerializableMode.NONE;
     }
 
-    public CreationSettings<T> setSerializableMode(SerializableMode serializableMode) {
-        this.serializableMode = serializableMode;
-        return this;
-    }
-
     @Override
-    public SerializableMode getSerializableMode() {
-        return serializableMode;
+    public boolean isLenient() {
+        return strictness == Strictness.LENIENT;
     }
 
     @Override
-    public List<InvocationListener> getInvocationListeners() {
-        return invocationListeners;
+    public List<VerificationStartedListener> getVerificationStartedListeners() {
+        return verificationStartedListeners;
     }
 
     @Override
-    public List<VerificationStartedListener> getVerificationStartedListeners() {
-        return verificationStartedListeners;
+    public Class<T> getTypeToMock() {
+        return typeToMock;
     }
 
     @Override
@@ -155,18 +116,18 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
     }
 
     @Override
-    public boolean isUsingConstructor() {
-        return useConstructor;
+    public Strictness getStrictness() {
+        return strictness;
     }
 
     @Override
-    public boolean isStripAnnotations() {
-        return stripAnnotations;
+    public Object getSpiedInstance() {
+        return spiedInstance;
     }
 
     @Override
-    public Object[] getConstructorArgs() {
-        return constructorArgs;
+    public SerializableMode getSerializableMode() {
+        return serializableMode;
     }
 
     @Override
@@ -174,28 +135,67 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
         return outerClassInstance;
     }
 
-    @Override
-    public boolean isStubOnly() {
-        return stubOnly;
+    public String getName() {
+        return name;
     }
 
     @Override
-    public boolean isLenient() {
-        return strictness == Strictness.LENIENT;
+    public MockName getMockName() {
+        return mockName;
     }
 
     @Override
-    public Strictness getStrictness() {
-        return strictness;
+    public String getMockMaker() {
+        return mockMaker;
     }
 
     @Override
-    public String getMockMaker() {
-        return mockMaker;
+    public List<InvocationListener> getInvocationListeners() {
+        return invocationListeners;
     }
 
     @Override
     public Type getGenericTypeToMock() {
         return genericTypeToMock;
     }
+
+    @Override
+    public Set<Class<?>> getExtraInterfaces() {
+        return extraInterfaces;
+    }
+
+    @Override
+    public Answer<Object> getDefaultAnswer() {
+        return defaultAnswer;
+    }
+
+    @Override
+    public Object[] getConstructorArgs() {
+        return constructorArgs;
+    }
+
+    public CreationSettings() {}
+
+    @SuppressWarnings("unchecked")
+    public CreationSettings(CreationSettings copy) {
+        // TODO can we have a reflection test here? We had a couple of bugs here in the past.
+        this.typeToMock = copy.typeToMock;
+        this.genericTypeToMock = copy.genericTypeToMock;
+        this.extraInterfaces = copy.extraInterfaces;
+        this.name = copy.name;
+        this.spiedInstance = copy.spiedInstance;
+        this.defaultAnswer = copy.defaultAnswer;
+        this.mockName = copy.mockName;
+        this.serializableMode = copy.serializableMode;
+        this.invocationListeners = copy.invocationListeners;
+        this.stubbingLookupListeners = copy.stubbingLookupListeners;
+        this.verificationStartedListeners = copy.verificationStartedListeners;
+        this.stubOnly = copy.stubOnly;
+        this.useConstructor = copy.isUsingConstructor();
+        this.outerClassInstance = copy.getOuterClassInstance();
+        this.constructorArgs = copy.getConstructorArgs();
+        this.strictness = copy.strictness;
+        this.stripAnnotations = copy.stripAnnotations;
+        this.mockMaker = copy.mockMaker;
+    }
 }
diff --git a/src/main/java/org/mockito/internal/MockitoCore.java b/src/main/java/org/mockito/internal/framework/MockitoCore.java
similarity index 98%
rename from src/main/java/org/mockito/internal/MockitoCore.java
rename to src/main/java/org/mockito/internal/framework/MockitoCore.java
index fd39f6a4a..fa2e6631b 100644
--- a/src/main/java/org/mockito/internal/MockitoCore.java
+++ b/src/main/java/org/mockito/internal/framework/MockitoCore.java
@@ -2,7 +2,7 @@
  * Copyright (c) 2007 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.internal;
+package org.mockito.internal.framework;
 
 import static org.mockito.internal.exceptions.Reporter.missingMethodInvocation;
 import static org.mockito.internal.exceptions.Reporter.mocksHaveToBePassedToVerifyNoMoreInteractions;
@@ -39,6 +39,9 @@ import org.mockito.MockedStatic;
 import org.mockito.MockingDetails;
 import org.mockito.exceptions.misusing.DoNotMockException;
 import org.mockito.exceptions.misusing.NotAMockException;
+import org.mockito.internal.InOrderImpl;
+import org.mockito.internal.MockedConstructionImpl;
+import org.mockito.internal.MockedStaticImpl;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.creation.MockSettingsImpl;
 import org.mockito.internal.invocation.finder.VerifiableInvocationsFinder;
@@ -58,8 +61,8 @@ import org.mockito.internal.verification.api.VerificationDataInOrder;
 import org.mockito.internal.verification.api.VerificationDataInOrderImpl;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.configuration.MockCreationSettings;
+import org.mockito.configuration.DoNotMockEnforcer;
 import org.mockito.plugins.MockMaker;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.LenientStubber;
@@ -74,51 +77,114 @@ public class MockitoCore {
     private static final Set<Class<?>> MOCKABLE_CLASSES =
             Collections.synchronizedSet(new HashSet<>());
 
-    public <T> T mock(Class<T> typeToMock, MockSettings settings) {
-        if (!(settings instanceof MockSettingsImpl)) {
-            throw new IllegalArgumentException(
-                    "Unexpected implementation of '"
-                            + settings.getClass().getCanonicalName()
-                            + "'\n"
-                            + "At the moment, you cannot provide your own implementations of that class.");
+    public <T> OngoingStubbing<T> when(T methodCall) {
+        MockingProgress mockingProgress = mockingProgress();
+        mockingProgress.stubbingStarted();
+        @SuppressWarnings("unchecked")
+        OngoingStubbing<T> stubbing = (OngoingStubbing<T>) mockingProgress.pullOngoingStubbing();
+        if (stubbing == null) {
+            mockingProgress.reset();
+            throw missingMethodInvocation();
         }
-        MockSettingsImpl impl = (MockSettingsImpl) settings;
-        MockCreationSettings<T> creationSettings = impl.build(typeToMock);
-        checkDoNotMockAnnotation(creationSettings.getTypeToMock(), creationSettings);
-        T mock = createMock(creationSettings);
-        mockingProgress().mockingStarted(mock, creationSettings);
-        return mock;
+        return stubbing;
     }
 
-    private void checkDoNotMockAnnotation(
-            Class<?> typeToMock, MockCreationSettings<?> creationSettings) {
-        checkDoNotMockAnnotationForType(typeToMock);
-        for (Class<?> aClass : creationSettings.getExtraInterfaces()) {
-            checkDoNotMockAnnotationForType(aClass);
-        }
+    public void verifyNoMoreInteractionsInOrder(List<Object> mocks, InOrderContext inOrderContext) {
+        mockingProgress().validateState();
+        VerificationDataInOrder data =
+                new VerificationDataInOrderImpl(
+                        inOrderContext, VerifiableInvocationsFinder.find(mocks), null);
+        VerificationModeFactory.noMoreInteractions().verifyInOrder(data);
     }
 
-    private static void checkDoNotMockAnnotationForType(Class<?> type) {
-        // Object and interfaces do not have a super class
-        if (type == null) {
-            return;
+    public void verifyNoMoreInteractions(Object... mocks) {
+        assertMocksNotEmpty(mocks);
+        mockingProgress().validateState();
+        for (Object mock : mocks) {
+            try {
+                if (mock == null) {
+                    throw nullPassedToVerifyNoMoreInteractions();
+                }
+                InvocationContainerImpl invocations = getInvocationContainer(mock);
+                assertNotStubOnlyMock(mock);
+                VerificationDataImpl data = new VerificationDataImpl(invocations, null);
+                noMoreInteractions().verify(data);
+            } catch (NotAMockException e) {
+                throw notAMockPassedToVerifyNoMoreInteractions();
+            }
         }
+    }
 
-        if (MOCKABLE_CLASSES.contains(type)) {
-            return;
+    public void verifyNoInteractions(Object... mocks) {
+        assertMocksNotEmpty(mocks);
+        mockingProgress().validateState();
+        for (Object mock : mocks) {
+            try {
+                if (mock == null) {
+                    throw nullPassedToVerifyNoMoreInteractions();
+                }
+                InvocationContainerImpl invocations = getInvocationContainer(mock);
+                assertNotStubOnlyMock(mock);
+                VerificationDataImpl data = new VerificationDataImpl(invocations, null);
+                noInteractions().verify(data);
+            } catch (NotAMockException e) {
+                throw notAMockPassedToVerifyNoMoreInteractions();
+            }
         }
+    }
 
-        String warning = DO_NOT_MOCK_ENFORCER.checkTypeForDoNotMockViolation(type);
-        if (warning != null) {
-            throw new DoNotMockException(warning);
+    public <T> T verify(T mock, VerificationMode mode) {
+        if (mock == null) {
+            throw nullPassedToVerify();
+        }
+        MockingDetails mockingDetails = mockingDetails(mock);
+        if (!mockingDetails.isMock()) {
+            throw notAMockPassedToVerify(mock.getClass());
         }
+        assertNotStubOnlyMock(mock);
+        MockHandler handler = mockingDetails.getMockHandler();
+        mock =
+                (T)
+                        VerificationStartedNotifier.notifyVerificationStarted(
+                                handler.getMockSettings().getVerificationStartedListeners(),
+                                mockingDetails);
 
-        checkDoNotMockAnnotationForType(type.getSuperclass());
-        for (Class<?> aClass : type.getInterfaces()) {
-            checkDoNotMockAnnotationForType(aClass);
+        MockingProgress mockingProgress = mockingProgress();
+        VerificationMode actualMode = mockingProgress.maybeVerifyLazily(mode);
+        mockingProgress.verificationStarted(
+                new MockAwareVerificationMode(
+                        mock, actualMode, mockingProgress.verificationListeners()));
+        return mock;
+    }
+
+    public void validateMockitoUsage() {
+        mockingProgress().validateState();
+    }
+
+    public Stubber stubber() {
+        return stubber(null);
+    }
+
+    public Stubber stubber(Strictness strictness) {
+        MockingProgress mockingProgress = mockingProgress();
+        mockingProgress.stubbingStarted();
+        mockingProgress.resetOngoingStubbing();
+        return new StubberImpl(strictness);
+    }
+
+    public <T> void reset(T... mocks) {
+        MockingProgress mockingProgress = mockingProgress();
+        mockingProgress.validateState();
+        mockingProgress.reset();
+        mockingProgress.resetOngoingStubbing();
+
+        for (T m : mocks) {
+            resetMock(m);
         }
+    }
 
-        MOCKABLE_CLASSES.add(type);
+    public MockingDetails mockingDetails(Object toInspect) {
+        return new DefaultMockingDetails(toInspect);
     }
 
     public <T> MockedStatic<T> mockStatic(Class<T> classToMock, MockSettings settings) {
@@ -168,118 +234,24 @@ public class MockitoCore {
         return new MockedConstructionImpl<>(control);
     }
 
-    public <T> OngoingStubbing<T> when(T methodCall) {
-        MockingProgress mockingProgress = mockingProgress();
-        mockingProgress.stubbingStarted();
-        @SuppressWarnings("unchecked")
-        OngoingStubbing<T> stubbing = (OngoingStubbing<T>) mockingProgress.pullOngoingStubbing();
-        if (stubbing == null) {
-            mockingProgress.reset();
-            throw missingMethodInvocation();
-        }
-        return stubbing;
-    }
-
-    public <T> T verify(T mock, VerificationMode mode) {
-        if (mock == null) {
-            throw nullPassedToVerify();
-        }
-        MockingDetails mockingDetails = mockingDetails(mock);
-        if (!mockingDetails.isMock()) {
-            throw notAMockPassedToVerify(mock.getClass());
+    public <T> T mock(Class<T> typeToMock, MockSettings settings) {
+        if (!(settings instanceof MockSettingsImpl)) {
+            throw new IllegalArgumentException(
+                    "Unexpected implementation of '"
+                            + settings.getClass().getCanonicalName()
+                            + "'\n"
+                            + "At the moment, you cannot provide your own implementations of that class.");
         }
-        assertNotStubOnlyMock(mock);
-        MockHandler handler = mockingDetails.getMockHandler();
-        mock =
-                (T)
-                        VerificationStartedNotifier.notifyVerificationStarted(
-                                handler.getMockSettings().getVerificationStartedListeners(),
-                                mockingDetails);
-
-        MockingProgress mockingProgress = mockingProgress();
-        VerificationMode actualMode = mockingProgress.maybeVerifyLazily(mode);
-        mockingProgress.verificationStarted(
-                new MockAwareVerificationMode(
-                        mock, actualMode, mockingProgress.verificationListeners()));
+        MockSettingsImpl impl = (MockSettingsImpl) settings;
+        MockCreationSettings<T> creationSettings = impl.build(typeToMock);
+        checkDoNotMockAnnotation(creationSettings.getTypeToMock(), creationSettings);
+        T mock = createMock(creationSettings);
+        mockingProgress().mockingStarted(mock, creationSettings);
         return mock;
     }
 
-    public <T> void reset(T... mocks) {
-        MockingProgress mockingProgress = mockingProgress();
-        mockingProgress.validateState();
-        mockingProgress.reset();
-        mockingProgress.resetOngoingStubbing();
-
-        for (T m : mocks) {
-            resetMock(m);
-        }
-    }
-
-    public <T> void clearInvocations(T... mocks) {
-        MockingProgress mockingProgress = mockingProgress();
-        mockingProgress.validateState();
-        mockingProgress.reset();
-        mockingProgress.resetOngoingStubbing();
-
-        for (T m : mocks) {
-            getInvocationContainer(m).clearInvocations();
-        }
-    }
-
-    public void verifyNoMoreInteractions(Object... mocks) {
-        assertMocksNotEmpty(mocks);
-        mockingProgress().validateState();
-        for (Object mock : mocks) {
-            try {
-                if (mock == null) {
-                    throw nullPassedToVerifyNoMoreInteractions();
-                }
-                InvocationContainerImpl invocations = getInvocationContainer(mock);
-                assertNotStubOnlyMock(mock);
-                VerificationDataImpl data = new VerificationDataImpl(invocations, null);
-                noMoreInteractions().verify(data);
-            } catch (NotAMockException e) {
-                throw notAMockPassedToVerifyNoMoreInteractions();
-            }
-        }
-    }
-
-    public void verifyNoInteractions(Object... mocks) {
-        assertMocksNotEmpty(mocks);
-        mockingProgress().validateState();
-        for (Object mock : mocks) {
-            try {
-                if (mock == null) {
-                    throw nullPassedToVerifyNoMoreInteractions();
-                }
-                InvocationContainerImpl invocations = getInvocationContainer(mock);
-                assertNotStubOnlyMock(mock);
-                VerificationDataImpl data = new VerificationDataImpl(invocations, null);
-                noInteractions().verify(data);
-            } catch (NotAMockException e) {
-                throw notAMockPassedToVerifyNoMoreInteractions();
-            }
-        }
-    }
-
-    public void verifyNoMoreInteractionsInOrder(List<Object> mocks, InOrderContext inOrderContext) {
-        mockingProgress().validateState();
-        VerificationDataInOrder data =
-                new VerificationDataInOrderImpl(
-                        inOrderContext, VerifiableInvocationsFinder.find(mocks), null);
-        VerificationModeFactory.noMoreInteractions().verifyInOrder(data);
-    }
-
-    private void assertMocksNotEmpty(Object[] mocks) {
-        if (mocks == null || mocks.length == 0) {
-            throw mocksHaveToBePassedToVerifyNoMoreInteractions();
-        }
-    }
-
-    private void assertNotStubOnlyMock(Object mock) {
-        if (getMockHandler(mock).getMockSettings().isStubOnly()) {
-            throw stubPassedToVerify(mock);
-        }
+    public LenientStubber lenient() {
+        return new DefaultLenientStubber();
     }
 
     public InOrder inOrder(Object... mocks) {
@@ -298,19 +270,17 @@ public class MockitoCore {
         return new InOrderImpl(Arrays.asList(mocks));
     }
 
-    public Stubber stubber() {
-        return stubber(null);
-    }
-
-    public Stubber stubber(Strictness strictness) {
-        MockingProgress mockingProgress = mockingProgress();
-        mockingProgress.stubbingStarted();
-        mockingProgress.resetOngoingStubbing();
-        return new StubberImpl(strictness);
-    }
-
-    public void validateMockitoUsage() {
-        mockingProgress().validateState();
+    public Object[] ignoreStubs(Object... mocks) {
+        for (Object m : mocks) {
+            InvocationContainerImpl container = getInvocationContainer(m);
+            List<Invocation> ins = container.getInvocations();
+            for (Invocation in : ins) {
+                if (in.stubInfo() != null) {
+                    in.ignoreForVerification();
+                }
+            }
+        }
+        return mocks;
     }
 
     /**
@@ -325,28 +295,61 @@ public class MockitoCore {
         return allInvocations.get(allInvocations.size() - 1);
     }
 
-    public Object[] ignoreStubs(Object... mocks) {
-        for (Object m : mocks) {
-            InvocationContainerImpl container = getInvocationContainer(m);
-            List<Invocation> ins = container.getInvocations();
-            for (Invocation in : ins) {
-                if (in.stubInfo() != null) {
-                    in.ignoreForVerification();
-                }
-            }
+    public <T> void clearInvocations(T... mocks) {
+        MockingProgress mockingProgress = mockingProgress();
+        mockingProgress.validateState();
+        mockingProgress.reset();
+        mockingProgress.resetOngoingStubbing();
+
+        for (T m : mocks) {
+            getInvocationContainer(m).clearInvocations();
         }
-        return mocks;
     }
 
-    public MockingDetails mockingDetails(Object toInspect) {
-        return new DefaultMockingDetails(toInspect);
+    public void clearAllCaches() {
+        MockUtil.clearAllCaches();
     }
 
-    public LenientStubber lenient() {
-        return new DefaultLenientStubber();
+    private static void checkDoNotMockAnnotationForType(Class<?> type) {
+        // Object and interfaces do not have a super class
+        if (type == null) {
+            return;
+        }
+
+        if (MOCKABLE_CLASSES.contains(type)) {
+            return;
+        }
+
+        String warning = DO_NOT_MOCK_ENFORCER.checkTypeForDoNotMockViolation(type);
+        if (warning != null) {
+            throw new DoNotMockException(warning);
+        }
+
+        checkDoNotMockAnnotationForType(type.getSuperclass());
+        for (Class<?> aClass : type.getInterfaces()) {
+            checkDoNotMockAnnotationForType(aClass);
+        }
+
+        MOCKABLE_CLASSES.add(type);
     }
 
-    public void clearAllCaches() {
-        MockUtil.clearAllCaches();
+    private void checkDoNotMockAnnotation(
+            Class<?> typeToMock, MockCreationSettings<?> creationSettings) {
+        checkDoNotMockAnnotationForType(typeToMock);
+        for (Class<?> aClass : creationSettings.getExtraInterfaces()) {
+            checkDoNotMockAnnotationForType(aClass);
+        }
+    }
+
+    private void assertNotStubOnlyMock(Object mock) {
+        if (getMockHandler(mock).getMockSettings().isStubOnly()) {
+            throw stubPassedToVerify(mock);
+        }
+    }
+
+    private void assertMocksNotEmpty(Object[] mocks) {
+        if (mocks == null || mocks.length == 0) {
+            throw mocksHaveToBePassedToVerifyNoMoreInteractions();
+        }
     }
 }
diff --git a/src/main/java/org/mockito/internal/handler/InvocationNotifierHandler.java b/src/main/java/org/mockito/internal/handler/InvocationNotifierHandler.java
index b1c84dfd9..1cb7dcfbc 100644
--- a/src/main/java/org/mockito/internal/handler/InvocationNotifierHandler.java
+++ b/src/main/java/org/mockito/internal/handler/InvocationNotifierHandler.java
@@ -12,7 +12,7 @@ import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MockHandler;
 import org.mockito.listeners.InvocationListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * Handler, that call all listeners wanted for this mock, before delegating it
diff --git a/src/main/java/org/mockito/internal/handler/MockHandlerFactory.java b/src/main/java/org/mockito/internal/handler/MockHandlerFactory.java
index c735cd43c..50ef41987 100644
--- a/src/main/java/org/mockito/internal/handler/MockHandlerFactory.java
+++ b/src/main/java/org/mockito/internal/handler/MockHandlerFactory.java
@@ -5,7 +5,7 @@
 package org.mockito.internal.handler;
 
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /** by Szczepan Faber, created at: 5/21/12 */
 public final class MockHandlerFactory {
diff --git a/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java b/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
index e58659a16..1eeca508b 100644
--- a/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
+++ b/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
@@ -20,7 +20,7 @@ import org.mockito.internal.verification.VerificationDataImpl;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.verification.VerificationMode;
 
 /**
diff --git a/src/main/java/org/mockito/internal/handler/NullResultGuardian.java b/src/main/java/org/mockito/internal/handler/NullResultGuardian.java
index 65de62e06..fb135d4b6 100644
--- a/src/main/java/org/mockito/internal/handler/NullResultGuardian.java
+++ b/src/main/java/org/mockito/internal/handler/NullResultGuardian.java
@@ -9,7 +9,7 @@ import static org.mockito.internal.util.Primitives.defaultValue;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * Protects the results from delegate MockHandler. Makes sure the results are valid.
diff --git a/src/main/java/org/mockito/internal/invocation/DefaultInvocationFactory.java b/src/main/java/org/mockito/internal/invocation/DefaultInvocationFactory.java
index 4921f4006..dced9ec96 100644
--- a/src/main/java/org/mockito/internal/invocation/DefaultInvocationFactory.java
+++ b/src/main/java/org/mockito/internal/invocation/DefaultInvocationFactory.java
@@ -14,7 +14,7 @@ import org.mockito.internal.progress.SequenceNumber;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationFactory;
 import org.mockito.invocation.Location;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 public class DefaultInvocationFactory implements InvocationFactory {
 
diff --git a/src/main/java/org/mockito/internal/junit/MismatchReportingTestListener.java b/src/main/java/org/mockito/internal/junit/MismatchReportingTestListener.java
index ec877b508..9264fdfc7 100644
--- a/src/main/java/org/mockito/internal/junit/MismatchReportingTestListener.java
+++ b/src/main/java/org/mockito/internal/junit/MismatchReportingTestListener.java
@@ -8,7 +8,7 @@ import java.util.Collection;
 import java.util.LinkedList;
 import java.util.List;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.MockitoLogger;
 
 /**
diff --git a/src/main/java/org/mockito/internal/junit/NoOpTestListener.java b/src/main/java/org/mockito/internal/junit/NoOpTestListener.java
index 77c7d4ecd..b43b959c5 100644
--- a/src/main/java/org/mockito/internal/junit/NoOpTestListener.java
+++ b/src/main/java/org/mockito/internal/junit/NoOpTestListener.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.junit;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 public class NoOpTestListener implements MockitoTestListener {
 
diff --git a/src/main/java/org/mockito/internal/junit/StrictStubsRunnerTestListener.java b/src/main/java/org/mockito/internal/junit/StrictStubsRunnerTestListener.java
index 8d6cc6c73..650376594 100644
--- a/src/main/java/org/mockito/internal/junit/StrictStubsRunnerTestListener.java
+++ b/src/main/java/org/mockito/internal/junit/StrictStubsRunnerTestListener.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.junit;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.quality.Strictness;
 
 /**
diff --git a/src/main/java/org/mockito/internal/junit/UniversalTestListener.java b/src/main/java/org/mockito/internal/junit/UniversalTestListener.java
index 72e3c0912..61c750e06 100644
--- a/src/main/java/org/mockito/internal/junit/UniversalTestListener.java
+++ b/src/main/java/org/mockito/internal/junit/UniversalTestListener.java
@@ -8,7 +8,7 @@ import java.util.Collection;
 import java.util.IdentityHashMap;
 import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.listeners.AutoCleanableListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.MockitoLogger;
 import org.mockito.quality.Strictness;
 
diff --git a/src/main/java/org/mockito/internal/junit/UnnecessaryStubbingsReporter.java b/src/main/java/org/mockito/internal/junit/UnnecessaryStubbingsReporter.java
index 2ba1fb962..befffca55 100644
--- a/src/main/java/org/mockito/internal/junit/UnnecessaryStubbingsReporter.java
+++ b/src/main/java/org/mockito/internal/junit/UnnecessaryStubbingsReporter.java
@@ -14,7 +14,7 @@ import org.junit.runner.notification.RunNotifier;
 import org.mockito.internal.exceptions.Reporter;
 import org.mockito.invocation.Invocation;
 import org.mockito.listeners.MockCreationListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * Reports unnecessary stubbings
diff --git a/src/main/java/org/mockito/internal/listeners/StubbingLookupNotifier.java b/src/main/java/org/mockito/internal/listeners/StubbingLookupNotifier.java
index 533162890..e5dacdf52 100644
--- a/src/main/java/org/mockito/internal/listeners/StubbingLookupNotifier.java
+++ b/src/main/java/org/mockito/internal/listeners/StubbingLookupNotifier.java
@@ -11,7 +11,7 @@ import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.invocation.Invocation;
 import org.mockito.listeners.StubbingLookupEvent;
 import org.mockito.listeners.StubbingLookupListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.Stubbing;
 
 public final class StubbingLookupNotifier {
diff --git a/src/main/java/org/mockito/internal/listeners/VerificationStartedNotifier.java b/src/main/java/org/mockito/internal/listeners/VerificationStartedNotifier.java
index 9a5a89060..bc2e6f800 100644
--- a/src/main/java/org/mockito/internal/listeners/VerificationStartedNotifier.java
+++ b/src/main/java/org/mockito/internal/listeners/VerificationStartedNotifier.java
@@ -13,7 +13,7 @@ import org.mockito.internal.exceptions.Reporter;
 import org.mockito.internal.matchers.text.ValuePrinter;
 import org.mockito.listeners.VerificationStartedEvent;
 import org.mockito.listeners.VerificationStartedListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 public final class VerificationStartedNotifier {
 
diff --git a/src/main/java/org/mockito/internal/progress/MockingProgress.java b/src/main/java/org/mockito/internal/progress/MockingProgress.java
index abdf68d83..bbf61acdd 100644
--- a/src/main/java/org/mockito/internal/progress/MockingProgress.java
+++ b/src/main/java/org/mockito/internal/progress/MockingProgress.java
@@ -8,7 +8,7 @@ import java.util.Set;
 
 import org.mockito.listeners.MockitoListener;
 import org.mockito.listeners.VerificationListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.OngoingStubbing;
 import org.mockito.verification.VerificationMode;
 import org.mockito.verification.VerificationStrategy;
diff --git a/src/main/java/org/mockito/internal/progress/MockingProgressImpl.java b/src/main/java/org/mockito/internal/progress/MockingProgressImpl.java
index 2585d32cf..740a07dc1 100644
--- a/src/main/java/org/mockito/internal/progress/MockingProgressImpl.java
+++ b/src/main/java/org/mockito/internal/progress/MockingProgressImpl.java
@@ -21,7 +21,7 @@ import org.mockito.invocation.Location;
 import org.mockito.listeners.MockCreationListener;
 import org.mockito.listeners.MockitoListener;
 import org.mockito.listeners.VerificationListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.OngoingStubbing;
 import org.mockito.verification.VerificationMode;
 import org.mockito.verification.VerificationStrategy;
diff --git a/src/main/java/org/mockito/internal/stubbing/DefaultLenientStubber.java b/src/main/java/org/mockito/internal/stubbing/DefaultLenientStubber.java
index 6986c20e3..9aa2fdd66 100644
--- a/src/main/java/org/mockito/internal/stubbing/DefaultLenientStubber.java
+++ b/src/main/java/org/mockito/internal/stubbing/DefaultLenientStubber.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.stubbing;
 
-import org.mockito.internal.MockitoCore;
+import org.mockito.internal.framework.MockitoCore;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Answer;
 import org.mockito.stubbing.LenientStubber;
diff --git a/src/main/java/org/mockito/internal/stubbing/InvocationContainerImpl.java b/src/main/java/org/mockito/internal/stubbing/InvocationContainerImpl.java
index 927d230e0..d336bfd32 100644
--- a/src/main/java/org/mockito/internal/stubbing/InvocationContainerImpl.java
+++ b/src/main/java/org/mockito/internal/stubbing/InvocationContainerImpl.java
@@ -19,7 +19,7 @@ import org.mockito.internal.verification.SingleRegisteredInvocation;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MatchableInvocation;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Answer;
 import org.mockito.stubbing.Stubbing;
diff --git a/src/main/java/org/mockito/internal/stubbing/StrictnessSelector.java b/src/main/java/org/mockito/internal/stubbing/StrictnessSelector.java
index c8e7e4440..4dea7b9ea 100644
--- a/src/main/java/org/mockito/internal/stubbing/StrictnessSelector.java
+++ b/src/main/java/org/mockito/internal/stubbing/StrictnessSelector.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.stubbing;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Stubbing;
 
diff --git a/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java b/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
index c159906af..43aba99ea 100644
--- a/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
+++ b/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
@@ -15,7 +15,7 @@ import org.mockito.internal.util.MockUtil;
 import org.mockito.internal.util.Primitives;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 public class InvocationInfo implements AbstractAwareMethod {
 
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
index 8b64a1691..494921efb 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
@@ -11,7 +11,7 @@ import java.lang.reflect.TypeVariable;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 final class RetrieveGenericsForDefaultAnswers {
 
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
index 27faed9d9..5fe0a11ab 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
@@ -12,14 +12,14 @@ import java.io.Serializable;
 
 import org.mockito.MockSettings;
 import org.mockito.Mockito;
-import org.mockito.internal.MockitoCore;
+import org.mockito.internal.framework.MockitoCore;
 import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.stubbing.StubbedInvocationMatcher;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.Answer;
 
 /**
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
index c15578091..3c3f98d88 100755
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
@@ -10,7 +10,7 @@ import org.mockito.Mockito;
 import org.mockito.internal.creation.MockSettingsImpl;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.invocation.InvocationOnMock;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.Answer;
 
 public class ReturnsMocks implements Answer<Object>, Serializable {
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
index d538784a9..6491fc00b 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
@@ -18,7 +18,7 @@ import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.invocation.Location;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.Answer;
 
 /**
diff --git a/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java b/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
index 1ad5a757f..9ac690c93 100644
--- a/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
+++ b/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
@@ -12,7 +12,7 @@ import org.mockito.internal.debugging.InvocationsPrinter;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.Stubbing;
 
 /**
diff --git a/src/main/java/org/mockito/internal/util/MockUtil.java b/src/main/java/org/mockito/internal/util/MockUtil.java
index 97b9b49cc..0d37bd43e 100644
--- a/src/main/java/org/mockito/internal/util/MockUtil.java
+++ b/src/main/java/org/mockito/internal/util/MockUtil.java
@@ -13,8 +13,9 @@ import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.util.reflection.LenientCopyTool;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.mock.MockName;
+import org.mockito.mock.MockNameImpl;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockMaker.TypeMockability;
 import org.mockito.plugins.MockResolver;
diff --git a/src/main/java/org/mockito/invocation/InvocationFactory.java b/src/main/java/org/mockito/invocation/InvocationFactory.java
index c28ef716b..3a1e48c6e 100644
--- a/src/main/java/org/mockito/invocation/InvocationFactory.java
+++ b/src/main/java/org/mockito/invocation/InvocationFactory.java
@@ -8,7 +8,7 @@ import java.io.Serializable;
 import java.lang.reflect.Method;
 
 import org.mockito.MockitoFramework;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * Available via {@link MockitoFramework#getInvocationFactory()}.
diff --git a/src/main/java/org/mockito/invocation/MockHandler.java b/src/main/java/org/mockito/invocation/MockHandler.java
index 56a0004ad..dec504c08 100644
--- a/src/main/java/org/mockito/invocation/MockHandler.java
+++ b/src/main/java/org/mockito/invocation/MockHandler.java
@@ -7,7 +7,7 @@ package org.mockito.invocation;
 import java.io.Serializable;
 
 import org.mockito.MockSettings;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * Mockito handler of an invocation on a mock. This is a core part of the API, the heart of Mockito.
diff --git a/src/main/java/org/mockito/listeners/MockCreationListener.java b/src/main/java/org/mockito/listeners/MockCreationListener.java
index 7ab15f823..64f111438 100644
--- a/src/main/java/org/mockito/listeners/MockCreationListener.java
+++ b/src/main/java/org/mockito/listeners/MockCreationListener.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.listeners;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * Notified when mock object is created.
diff --git a/src/main/java/org/mockito/listeners/StubbingLookupEvent.java b/src/main/java/org/mockito/listeners/StubbingLookupEvent.java
index 30642cca6..4d9ccc158 100644
--- a/src/main/java/org/mockito/listeners/StubbingLookupEvent.java
+++ b/src/main/java/org/mockito/listeners/StubbingLookupEvent.java
@@ -7,7 +7,7 @@ package org.mockito.listeners;
 import java.util.Collection;
 
 import org.mockito.invocation.Invocation;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.Stubbing;
 
 /**
diff --git a/src/main/java/org/mockito/listeners/StubbingLookupListener.java b/src/main/java/org/mockito/listeners/StubbingLookupListener.java
index b33e06346..5f9e3d4d0 100644
--- a/src/main/java/org/mockito/listeners/StubbingLookupListener.java
+++ b/src/main/java/org/mockito/listeners/StubbingLookupListener.java
@@ -5,7 +5,7 @@
 package org.mockito.listeners;
 
 import org.mockito.MockSettings;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * When a method is called on a mock object Mockito looks up any stubbings recorded on that mock.
diff --git a/src/main/java/org/mockito/internal/util/MockNameImpl.java b/src/main/java/org/mockito/mock/MockNameImpl.java
similarity index 96%
rename from src/main/java/org/mockito/internal/util/MockNameImpl.java
rename to src/main/java/org/mockito/mock/MockNameImpl.java
index 637468769..4f54c70da 100644
--- a/src/main/java/org/mockito/internal/util/MockNameImpl.java
+++ b/src/main/java/org/mockito/mock/MockNameImpl.java
@@ -2,30 +2,19 @@
  * Copyright (c) 2007 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.internal.util;
+package org.mockito.mock;
 
 import java.io.Serializable;
 
-import org.mockito.mock.MockName;
-
 public class MockNameImpl implements MockName, Serializable {
 
     private static final long serialVersionUID = 8014974700844306925L;
     private final String mockName;
     private boolean defaultName;
 
-    @SuppressWarnings("unchecked")
-    public MockNameImpl(String mockName, Class<?> type, boolean mockedStatic) {
-        if (mockName == null) {
-            this.mockName = mockedStatic ? toClassName(type) : toInstanceName(type);
-            this.defaultName = true;
-        } else {
-            this.mockName = mockName;
-        }
-    }
-
-    public MockNameImpl(String mockName) {
-        this.mockName = mockName;
+    @Override
+    public String toString() {
+        return mockName;
     }
 
     private static String toInstanceName(Class<?> clazz) {
@@ -52,8 +41,17 @@ public class MockNameImpl implements MockName, Serializable {
         return defaultName;
     }
 
-    @Override
-    public String toString() {
-        return mockName;
+    @SuppressWarnings("unchecked")
+    public MockNameImpl(String mockName, Class<?> type, boolean mockedStatic) {
+        if (mockName == null) {
+            this.mockName = mockedStatic ? toClassName(type) : toInstanceName(type);
+            this.defaultName = true;
+        } else {
+            this.mockName = mockName;
+        }
+    }
+
+    public MockNameImpl(String mockName) {
+        this.mockName = mockName;
     }
 }
diff --git a/src/main/java/org/mockito/plugins/InstantiatorProvider2.java b/src/main/java/org/mockito/plugins/InstantiatorProvider2.java
index 3bc1f322c..9c4c41894 100644
--- a/src/main/java/org/mockito/plugins/InstantiatorProvider2.java
+++ b/src/main/java/org/mockito/plugins/InstantiatorProvider2.java
@@ -5,7 +5,7 @@
 package org.mockito.plugins;
 
 import org.mockito.creation.instance.Instantiator;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * <p>
diff --git a/src/main/java/org/mockito/plugins/MockMaker.java b/src/main/java/org/mockito/plugins/MockMaker.java
index c0b1cbcd2..132e5435b 100644
--- a/src/main/java/org/mockito/plugins/MockMaker.java
+++ b/src/main/java/org/mockito/plugins/MockMaker.java
@@ -8,7 +8,7 @@ import org.mockito.MockSettings;
 import org.mockito.MockedConstruction;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 import java.util.List;
 import java.util.Optional;
@@ -59,7 +59,7 @@ import static org.mockito.internal.util.StringUtil.join;
  *             .mockMaker("org.awesome.mockito.AwesomeMockMaker"));
  * </pre>
  *
- * @see org.mockito.mock.MockCreationSettings
+ * @see MockCreationSettings
  * @see org.mockito.invocation.MockHandler
  * @since 1.9.5
  */
diff --git a/src/test/java/org/mockito/internal/creation/AbstractMockMakerTest.java b/src/test/java/org/mockito/internal/creation/AbstractMockMakerTest.java
index d59477829..72ce93b35 100644
--- a/src/test/java/org/mockito/internal/creation/AbstractMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/AbstractMockMakerTest.java
@@ -10,7 +10,7 @@ import org.mockito.internal.stubbing.answers.CallsRealMethods;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 import org.mockito.stubbing.Answer;
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/AbstractByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/AbstractByteBuddyMockMakerTest.java
index 93c8913ac..ac6ff6c05 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/AbstractByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/AbstractByteBuddyMockMakerTest.java
@@ -16,7 +16,7 @@ import org.mockito.Mockito;
 import org.mockito.internal.creation.AbstractMockMakerTest;
 import org.mockito.internal.handler.MockHandlerImpl;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 import org.mockitoutil.ClassLoaders;
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMakerTest.java
index dc341d895..fb1927206 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMakerTest.java
@@ -30,7 +30,7 @@ import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.handler.MockHandlerImpl;
 import org.mockito.internal.stubbing.answers.Returns;
 import org.mockito.internal.util.collections.Sets;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 
diff --git a/src/test/java/org/mockito/internal/framework/DefaultMockitoFrameworkTest.java b/src/test/java/org/mockito/internal/framework/DefaultMockitoFrameworkTest.java
index 3b2884e52..aab4b3db1 100644
--- a/src/test/java/org/mockito/internal/framework/DefaultMockitoFrameworkTest.java
+++ b/src/test/java/org/mockito/internal/framework/DefaultMockitoFrameworkTest.java
@@ -29,7 +29,7 @@ import org.mockito.exceptions.misusing.RedundantListenerException;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.listeners.MockCreationListener;
 import org.mockito.listeners.MockitoListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.InlineMockMaker;
 import org.mockitoutil.TestBase;
 
diff --git a/src/test/java/org/mockito/internal/handler/InvocationNotifierHandlerTest.java b/src/test/java/org/mockito/internal/handler/InvocationNotifierHandlerTest.java
index 54e8394c0..3c1f3c279 100644
--- a/src/test/java/org/mockito/internal/handler/InvocationNotifierHandlerTest.java
+++ b/src/test/java/org/mockito/internal/handler/InvocationNotifierHandlerTest.java
@@ -27,7 +27,7 @@ import org.mockito.invocation.Invocation;
 import org.mockito.junit.MockitoJUnitRunner;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.listeners.MethodInvocationReport;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.stubbing.Answer;
 
 @RunWith(MockitoJUnitRunner.class)
diff --git a/src/test/java/org/mockito/internal/handler/MockHandlerFactoryTest.java b/src/test/java/org/mockito/internal/handler/MockHandlerFactoryTest.java
index d82bc7829..2ae59f9fb 100644
--- a/src/test/java/org/mockito/internal/handler/MockHandlerFactoryTest.java
+++ b/src/test/java/org/mockito/internal/handler/MockHandlerFactoryTest.java
@@ -14,7 +14,7 @@ import org.mockito.internal.creation.MockSettingsImpl;
 import org.mockito.internal.stubbing.answers.Returns;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockitousage.IMethods;
 import org.mockitoutil.TestBase;
 
diff --git a/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplTest.java b/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplTest.java
index aef75eea4..a707f80ee 100644
--- a/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplTest.java
+++ b/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplTest.java
@@ -18,7 +18,7 @@ import org.mockito.internal.invocation.InvocationMatcher;
 import org.mockito.internal.stubbing.answers.Returns;
 import org.mockito.internal.stubbing.defaultanswers.ReturnsEmptyValues;
 import org.mockito.invocation.Invocation;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 /**
  * Author: Szczepan Faber
diff --git a/src/test/java/org/mockito/internal/stubbing/answers/CallsRealMethodsTest.java b/src/test/java/org/mockito/internal/stubbing/answers/CallsRealMethodsTest.java
index f8d904f2b..b31a25c84 100644
--- a/src/test/java/org/mockito/internal/stubbing/answers/CallsRealMethodsTest.java
+++ b/src/test/java/org/mockito/internal/stubbing/answers/CallsRealMethodsTest.java
@@ -13,7 +13,7 @@ import java.util.ArrayList;
 import org.assertj.core.api.Assertions;
 import org.junit.Test;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.MockitoCore;
+import org.mockito.internal.framework.MockitoCore;
 import org.mockito.internal.invocation.InvocationBuilder;
 import org.mockito.invocation.Invocation;
 
diff --git a/src/test/java/org/mockito/internal/util/MockNameImplTest.java b/src/test/java/org/mockito/internal/util/MockNameImplTest.java
index 583bd7ac0..60d2986c3 100644
--- a/src/test/java/org/mockito/internal/util/MockNameImplTest.java
+++ b/src/test/java/org/mockito/internal/util/MockNameImplTest.java
@@ -7,6 +7,7 @@ package org.mockito.internal.util;
 import static org.junit.Assert.assertEquals;
 
 import org.junit.Test;
+import org.mockito.mock.MockNameImpl;
 import org.mockitoutil.TestBase;
 
 public class MockNameImplTest extends TestBase {
diff --git a/src/test/java/org/mockito/internal/util/MockSettingsTest.java b/src/test/java/org/mockito/internal/util/MockSettingsTest.java
index ab39828b1..eb95c3e30 100644
--- a/src/test/java/org/mockito/internal/util/MockSettingsTest.java
+++ b/src/test/java/org/mockito/internal/util/MockSettingsTest.java
@@ -12,7 +12,7 @@ import java.util.List;
 import org.junit.Test;
 import org.mockito.Mockito;
 import org.mockito.internal.creation.settings.CreationSettings;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockitoutil.TestBase;
 
 public class MockSettingsTest extends TestBase {
diff --git a/src/test/java/org/mockitointegration/DeferMockMakersClassLoadingTest.java b/src/test/java/org/mockitointegration/DeferMockMakersClassLoadingTest.java
index 63c0d761b..bfe9e2e39 100644
--- a/src/test/java/org/mockitointegration/DeferMockMakersClassLoadingTest.java
+++ b/src/test/java/org/mockitointegration/DeferMockMakersClassLoadingTest.java
@@ -18,7 +18,7 @@ import org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker;
 import org.mockito.internal.creation.bytebuddy.SubclassByteBuddyMockMaker;
 import org.mockito.internal.creation.proxy.ProxyMockMaker;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.MockMaker;
 import org.mockitoutil.ClassLoaders;
 
diff --git a/src/test/java/org/mockitousage/debugging/StubbingLookupListenerCallbackTest.java b/src/test/java/org/mockitousage/debugging/StubbingLookupListenerCallbackTest.java
index aa22e538a..5442c18dc 100644
--- a/src/test/java/org/mockitousage/debugging/StubbingLookupListenerCallbackTest.java
+++ b/src/test/java/org/mockitousage/debugging/StubbingLookupListenerCallbackTest.java
@@ -18,7 +18,7 @@ import org.mockito.ArgumentMatcher;
 import org.mockito.InOrder;
 import org.mockito.listeners.StubbingLookupEvent;
 import org.mockito.listeners.StubbingLookupListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockitousage.IMethods;
 import org.mockitoutil.ConcurrentTesting;
 import org.mockitoutil.TestBase;
diff --git a/src/test/java/org/mockitoutil/TestBase.java b/src/test/java/org/mockitoutil/TestBase.java
index 3f772d020..2d1693eef 100644
--- a/src/test/java/org/mockitoutil/TestBase.java
+++ b/src/test/java/org/mockitoutil/TestBase.java
@@ -15,7 +15,7 @@ import org.junit.After;
 import org.junit.Before;
 import org.mockito.MockitoAnnotations;
 import org.mockito.StateMaster;
-import org.mockito.internal.MockitoCore;
+import org.mockito.internal.framework.MockitoCore;
 import org.mockito.internal.configuration.ConfigurationAccess;
 import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.invocation.InterceptedInvocation;
diff --git a/subprojects/android/src/main/java/org/mockito/android/internal/creation/AndroidByteBuddyMockMaker.java b/subprojects/android/src/main/java/org/mockito/android/internal/creation/AndroidByteBuddyMockMaker.java
index 64f6d70aa..1426794a7 100644
--- a/subprojects/android/src/main/java/org/mockito/android/internal/creation/AndroidByteBuddyMockMaker.java
+++ b/subprojects/android/src/main/java/org/mockito/android/internal/creation/AndroidByteBuddyMockMaker.java
@@ -8,7 +8,7 @@ import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.creation.bytebuddy.SubclassByteBuddyMockMaker;
 import org.mockito.internal.util.Platform;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 import org.mockito.plugins.MockMaker;
 
 import static org.mockito.internal.util.StringUtil.join;
diff --git a/subprojects/extTest/src/test/java/org/mockitousage/plugins/donotmockenforcer/MyDoNotMockEnforcer.java b/subprojects/extTest/src/test/java/org/mockitousage/plugins/donotmockenforcer/MyDoNotMockEnforcer.java
index 73ca83017..a0fb4e842 100644
--- a/subprojects/extTest/src/test/java/org/mockitousage/plugins/donotmockenforcer/MyDoNotMockEnforcer.java
+++ b/subprojects/extTest/src/test/java/org/mockitousage/plugins/donotmockenforcer/MyDoNotMockEnforcer.java
@@ -4,7 +4,7 @@
  */
 package org.mockitousage.plugins.donotmockenforcer;
 
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.configuration.DoNotMockEnforcer;
 
 public class MyDoNotMockEnforcer implements DoNotMockEnforcer {
 
diff --git a/subprojects/extTest/src/test/java/org/mockitousage/plugins/instantiator/MyInstantiatorProvider2.java b/subprojects/extTest/src/test/java/org/mockitousage/plugins/instantiator/MyInstantiatorProvider2.java
index e4238f3a6..bd9bbfb50 100644
--- a/subprojects/extTest/src/test/java/org/mockitousage/plugins/instantiator/MyInstantiatorProvider2.java
+++ b/subprojects/extTest/src/test/java/org/mockitousage/plugins/instantiator/MyInstantiatorProvider2.java
@@ -7,7 +7,7 @@ package org.mockitousage.plugins.instantiator;
 import org.mockito.creation.instance.InstantiationException;
 import org.mockito.creation.instance.Instantiator;
 import org.mockito.internal.creation.instance.DefaultInstantiatorProvider;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 public class MyInstantiatorProvider2 extends DefaultInstantiatorProvider {
     static ThreadLocal<Boolean> explosive = new ThreadLocal<>();
diff --git a/subprojects/extTest/src/test/java/org/mockitousage/plugins/switcher/MyMockMaker.java b/subprojects/extTest/src/test/java/org/mockitousage/plugins/switcher/MyMockMaker.java
index d412beda9..0159e555f 100644
--- a/subprojects/extTest/src/test/java/org/mockitousage/plugins/switcher/MyMockMaker.java
+++ b/subprojects/extTest/src/test/java/org/mockitousage/plugins/switcher/MyMockMaker.java
@@ -6,7 +6,7 @@ package org.mockitousage.plugins.switcher;
 
 import org.mockito.internal.creation.bytebuddy.SubclassByteBuddyMockMaker;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 public class MyMockMaker extends SubclassByteBuddyMockMaker {
 
diff --git a/subprojects/programmatic-test/src/test/java/org/mockito/ProgrammaticMockMakerTest.java b/subprojects/programmatic-test/src/test/java/org/mockito/ProgrammaticMockMakerTest.java
index f03555d0e..5dfe3397b 100644
--- a/subprojects/programmatic-test/src/test/java/org/mockito/ProgrammaticMockMakerTest.java
+++ b/subprojects/programmatic-test/src/test/java/org/mockito/ProgrammaticMockMakerTest.java
@@ -16,7 +16,7 @@ import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.verification.SmartNullPointerException;
 import org.mockito.internal.creation.bytebuddy.SubclassByteBuddyMockMaker;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.configuration.MockCreationSettings;
 
 public final class ProgrammaticMockMakerTest {
     @Test

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

