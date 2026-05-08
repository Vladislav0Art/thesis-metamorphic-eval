#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout edc624371009ce981bbc11b7d125ff4e359cff7e

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/Mockito.java b/src/main/java/org/mockito/Mockito.java
index ee5a13303..3d3585bc6 100644
--- a/src/main/java/org/mockito/Mockito.java
+++ b/src/main/java/org/mockito/Mockito.java
@@ -10,7 +10,7 @@ import org.mockito.internal.MockitoCore;
 import org.mockito.internal.creation.MockSettingsImpl;
 import org.mockito.internal.framework.DefaultMockitoFramework;
 import org.mockito.internal.session.DefaultMockitoSessionBuilder;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.verification.VerificationModeFactory;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationFactory;
@@ -23,7 +23,7 @@ import org.mockito.listeners.VerificationStartedEvent;
 import org.mockito.listeners.VerificationStartedListener;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.infra.MockitoPluginRegistry;
 import org.mockito.quality.MockitoHint;
 import org.mockito.quality.Strictness;
 import org.mockito.session.MockitoSessionBuilder;
@@ -1421,7 +1421,7 @@ import java.util.function.Function;
  * During the design and implementation process (<a href="https://github.com/mockito/mockito/issues/1110">issue 1110</a>)
  * we have developed and changed following public API elements:
  * <ul>
- *     <li>New {@link MockitoPlugins} -
+ *     <li>New {@link MockitoPluginRegistry} -
  *      Enables framework integrators to get access to default Mockito plugins.
  *      Useful when one needs to implement custom plugin such as {@link MockMaker}
  *      and delegate some behavior to the default Mockito implementation.
@@ -2181,7 +2181,7 @@ public class Mockito extends ArgumentMatchers {
      * @return a spy of the real object
      */
     public static <T> T spy(T object) {
-        if (MockUtil.isMock(object)) {
+        if (MockUtilities.isMock(object)) {
             throw new IllegalArgumentException(
                     "Please don't pass mock here. Spy is not allowed on mock.");
         }
diff --git a/src/main/java/org/mockito/MockitoFramework.java b/src/main/java/org/mockito/MockitoFramework.java
index 020186f05..697d6abff 100644
--- a/src/main/java/org/mockito/MockitoFramework.java
+++ b/src/main/java/org/mockito/MockitoFramework.java
@@ -8,7 +8,7 @@ import org.mockito.exceptions.misusing.RedundantListenerException;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationFactory;
 import org.mockito.listeners.MockitoListener;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.infra.MockitoPluginRegistry;
 
 /**
  * Mockito framework settings and lifecycle listeners, for advanced users or for integrating with other frameworks.
@@ -73,12 +73,12 @@ public interface MockitoFramework {
     /**
      * Returns an object that has access to Mockito plugins.
      * An example plugin is {@link org.mockito.plugins.MockMaker}.
-     * For information why and how to use this method see {@link MockitoPlugins}.
+     * For information why and how to use this method see {@link MockitoPluginRegistry}.
      *
      * @return object that gives access to mockito plugins
      * @since 2.10.0
      */
-    MockitoPlugins getPlugins();
+    MockitoPluginRegistry getPlugins();
 
     /**
      * Returns a factory that can create instances of {@link Invocation}.
diff --git a/src/main/java/org/mockito/internal/MockUtilities.java b/src/main/java/org/mockito/internal/MockUtilities.java
new file mode 100644
index 000000000..a6c8a81d4
--- /dev/null
+++ b/src/main/java/org/mockito/internal/MockUtilities.java
@@ -0,0 +1,221 @@
+/*
+ * Copyright (c) 2007 Mockito contributors
+ * This program is made available under the terms of the MIT License.
+ */
+package org.mockito.internal;
+
+import org.mockito.MockedConstruction;
+import org.mockito.Mockito;
+import org.mockito.exceptions.misusing.NotAMockException;
+import org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry;
+import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.stubbing.InvocationContainerImpl;
+import org.mockito.internal.util.MockNameImpl;
+import org.mockito.internal.util.reflection.LenientCopyTool;
+import org.mockito.invocation.MockHandler;
+import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockName;
+import org.mockito.plugins.MockMaker;
+import org.mockito.plugins.MockMaker.TypeMockability;
+import org.mockito.plugins.MockResolver;
+
+import java.util.Collections;
+import java.util.Map;
+import java.util.concurrent.ConcurrentHashMap;
+import java.util.function.Function;
+
+import static org.mockito.internal.handler.MockHandlerFactory.createMockHandler;
+
+@SuppressWarnings("unchecked")
+public class MockUtilities {
+
+    private static final MockMaker DEFAULT_FACTORY = Plugins.getMockMaker();
+    private static final Map<Class<? extends MockMaker>, MockMaker> MAKER_REGISTRY =
+            new ConcurrentHashMap<>(
+                    Collections.singletonMap(DEFAULT_FACTORY.getClass(), DEFAULT_FACTORY));
+
+    private static Object resolveMock(Object mockInstance) {
+        if (mockInstance instanceof Class<?>) { // static mocks are resolved by definition
+            return mockInstance;
+        }
+        for (MockResolver resolver : Plugins.getMockResolvers()) {
+            mockInstance = resolver.resolve(mockInstance);
+        }
+        return mockInstance;
+    }
+
+    public static void resetMockHandler(Object mockInstance) {
+        MockHandler previousHandler = getMockHandler(mockInstance);
+        MockCreationSettings creationSettings = previousHandler.getMockSettings();
+        MockHandler replacementHandler = createMockHandler(creationSettings);
+
+        mockInstance = resolveMock(mockInstance);
+        getMockMaker(creationSettings.getMockMaker()).resetMock(mockInstance, replacementHandler, creationSettings);
+    }
+
+    public static void redefineMockNameIfDefault(Object mockInstance, String replacementName) {
+        MockName resolvedName = getMockName(mockInstance);
+        // TODO SF hacky...
+        MockCreationSettings creationSettings = getMockHandler(mockInstance).getMockSettings();
+        if (resolvedName.isDefault() && creationSettings instanceof CreationSettings) {
+            ((CreationSettings) creationSettings).setMockName(new MockNameImpl(replacementName));
+        }
+    }
+
+    public static TypeMockability isTypeMockable(Class<?> makerClass, String makerName) {
+        return getMockMaker(makerName).isTypeMockable(makerClass);
+    }
+
+    public static boolean isSpy(Object mockInstance) {
+        return isMock(mockInstance)
+                && getMockSettings(mockInstance).getDefaultAnswer() == Mockito.CALLS_REAL_METHODS;
+    }
+
+    public static boolean isMock(Object mockInstance) {
+        // TODO SF (perf tweak) in our codebase we call mockMaker.getHandler() multiple times
+        // unnecessarily
+        // This is not ideal because getHandler() can be expensive (reflective calls inside mock
+        // maker)
+        // The frequent pattern in the codebase are separate calls to: 1) isMock(mock) then 2)
+        // getMockHandler(mock)
+        // We could replace it with using mockingDetails().isMock()
+        // Let's refactor the codebase and use new mockingDetails() in all relevant places.
+        // Potentially we could also move other methods to MockitoMock, some other candidates:
+        // getInvocationContainer, isSpy, etc.
+        // This also allows us to reuse our public API MockingDetails
+        if (mockInstance == null) {
+            return false;
+        }
+        return getMockHandlerOrNull(mockInstance) != null;
+    }
+
+    public static MockCreationSettings getMockSettings(Object mockInstance) {
+        return getMockHandler(mockInstance).getMockSettings();
+    }
+
+    public static MockName getMockName(Object mockInstance) {
+        return getMockHandler(mockInstance).getMockSettings().getMockName();
+    }
+
+    private static MockMaker getMockMaker(String makerName) {
+        if (makerName == null) {
+            return DEFAULT_FACTORY;
+        }
+
+        String className;
+        if (DefaultMockitoPluginRegistry.MOCK_MAKER_ALIASES.contains(makerName)) {
+            className = DefaultMockitoPluginRegistry.getDefaultPluginClass(makerName);
+        } else {
+            className = makerName;
+        }
+
+        Class<? extends MockMaker> makerClass;
+        // Using the context class loader because PluginInitializer.loadImpl is using it as well.
+        // Personally, I am suspicious whether the context class loader is a good choice in either
+        // of these cases.
+        ClassLoader classLoader = Thread.currentThread().getContextClassLoader();
+        if (classLoader == null) {
+            classLoader = ClassLoader.getSystemClassLoader();
+        }
+        try {
+            makerClass = classLoader.loadClass(className).asSubclass(MockMaker.class);
+        } catch (Exception ex) {
+            throw new IllegalStateException("Failed to load MockMaker: " + makerName, ex);
+        }
+
+        return MAKER_REGISTRY.computeIfAbsent(
+            makerClass,
+            targetClass -> {
+                    try {
+                        return targetClass.getDeclaredConstructor().newInstance();
+                    } catch (Exception ex) {
+                        throw new IllegalStateException(
+                                "Failed to construct MockMaker: " + targetClass.getName(), ex);
+                    }
+                });
+    }
+
+    private static MockHandler<?> getMockHandlerOrNull(Object mockInstance) {
+        if (mockInstance == null) {
+            throw new NotAMockException("Argument should be a mock, but is null!");
+        }
+
+        mockInstance = resolveMock(mockInstance);
+
+        for (MockMaker makerName : MAKER_REGISTRY.values()) {
+            MockHandler<?> foundHandler = makerName.getHandler(mockInstance);
+            if (foundHandler != null) {
+                assert getMockMaker(foundHandler.getMockSettings().getMockMaker()) == makerName;
+                return foundHandler;
+            }
+        }
+        return null;
+    }
+
+    public static MockHandler<?> getMockHandler(Object mockInstance) {
+        MockHandler foundHandler = getMockHandlerOrNull(mockInstance);
+        if (foundHandler != null) {
+            return foundHandler;
+        } else {
+            throw new NotAMockException("Argument should be a mock, but is: " + mockInstance.getClass());
+        }
+    }
+
+    public static InvocationContainerImpl getInvocationContainer(Object mockInstance) {
+        return (InvocationContainerImpl) getMockHandler(mockInstance).getInvocationContainer();
+    }
+
+    public static <T> MockMaker.StaticMockControl<T> createStaticClassMock(
+        Class<T> makerClass, MockCreationSettings<T> creationSettings) {
+        MockMaker makerName = getMockMaker(creationSettings.getMockMaker());
+        MockHandler<T> foundHandler = createMockHandler(creationSettings);
+        return makerName.createStaticMock(makerClass, creationSettings, foundHandler);
+    }
+
+    public static <T> MockMaker.ConstructionMockControl<T> createMockedConstruction(
+            Class<T> makerClass,
+            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsProvider,
+            MockedConstruction.MockInitializer<T> initializer) {
+        Function<MockedConstruction.Context, MockHandler<T>> handlerProvider =
+            ctx -> createMockHandler(settingsProvider.apply(ctx));
+        return DEFAULT_FACTORY.createConstructionMock(
+            makerClass, settingsProvider, handlerProvider, initializer);
+    }
+
+    public static <T> T createMockInstance(MockCreationSettings<T> creationSettings) {
+        MockMaker makerName = getMockMaker(creationSettings.getMockMaker());
+        MockHandler handler = createMockHandler(creationSettings);
+
+        Object spyTarget = creationSettings.getSpiedInstance();
+
+        T mockInstance;
+        if (spyTarget != null) {
+            mockInstance =
+                    makerName
+                            .createSpy(creationSettings, handler, (T) spyTarget)
+                            .orElseGet(
+                                    () -> {
+                                        T realInstance = makerName.createMock(creationSettings, handler);
+                                        new LenientCopyTool().copyToMock(spyTarget, realInstance);
+                                        return realInstance;
+                                    });
+        } else {
+            mockInstance = makerName.createMock(creationSettings, handler);
+        }
+
+        return mockInstance;
+    }
+
+    public static void clearCaches() {
+        for (MockMaker makerName : MAKER_REGISTRY.values()) {
+            makerName.clearAllCaches();
+        }
+    }
+
+    public static boolean areMocksSame(Object firstCandidate, Object secondCandidate) {
+        return firstCandidate == secondCandidate || resolveMock(firstCandidate) == resolveMock(secondCandidate);
+    }
+
+    private MockUtilities() {}
+}
diff --git a/src/main/java/org/mockito/internal/MockedStaticImpl.java b/src/main/java/org/mockito/internal/MockedStaticImpl.java
index f6705fb81..d9f862628 100644
--- a/src/main/java/org/mockito/internal/MockedStaticImpl.java
+++ b/src/main/java/org/mockito/internal/MockedStaticImpl.java
@@ -6,8 +6,8 @@ package org.mockito.internal;
 
 import static org.mockito.internal.exceptions.Reporter.missingMethodInvocation;
 import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
-import static org.mockito.internal.util.MockUtil.getInvocationContainer;
-import static org.mockito.internal.util.MockUtil.resetMock;
+import static org.mockito.internal.MockUtilities.getInvocationContainer;
+import static org.mockito.internal.MockUtilities.resetMockHandler;
 import static org.mockito.internal.util.StringUtil.join;
 import static org.mockito.internal.verification.VerificationModeFactory.noInteractions;
 import static org.mockito.internal.verification.VerificationModeFactory.noMoreInteractions;
@@ -109,7 +109,7 @@ public final class MockedStaticImpl<T> implements MockedStatic<T> {
         mockingProgress.reset();
         mockingProgress.resetOngoingStubbing();
 
-        resetMock(control.getType());
+        resetMockHandler(control.getType());
     }
 
     @Override
diff --git a/src/main/java/org/mockito/internal/MockitoCore.java b/src/main/java/org/mockito/internal/MockitoCore.java
index fd39f6a4a..eebb22d04 100644
--- a/src/main/java/org/mockito/internal/MockitoCore.java
+++ b/src/main/java/org/mockito/internal/MockitoCore.java
@@ -15,13 +15,13 @@ import static org.mockito.internal.exceptions.Reporter.nullPassedToVerifyNoMoreI
 import static org.mockito.internal.exceptions.Reporter.nullPassedWhenCreatingInOrder;
 import static org.mockito.internal.exceptions.Reporter.stubPassedToVerify;
 import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
-import static org.mockito.internal.util.MockUtil.createConstructionMock;
-import static org.mockito.internal.util.MockUtil.createMock;
-import static org.mockito.internal.util.MockUtil.createStaticMock;
-import static org.mockito.internal.util.MockUtil.getInvocationContainer;
-import static org.mockito.internal.util.MockUtil.getMockHandler;
-import static org.mockito.internal.util.MockUtil.isMock;
-import static org.mockito.internal.util.MockUtil.resetMock;
+import static org.mockito.internal.MockUtilities.createMockedConstruction;
+import static org.mockito.internal.MockUtilities.createMockInstance;
+import static org.mockito.internal.MockUtilities.createStaticClassMock;
+import static org.mockito.internal.MockUtilities.getInvocationContainer;
+import static org.mockito.internal.MockUtilities.getMockHandler;
+import static org.mockito.internal.MockUtilities.isMock;
+import static org.mockito.internal.MockUtilities.resetMockHandler;
 import static org.mockito.internal.verification.VerificationModeFactory.noInteractions;
 import static org.mockito.internal.verification.VerificationModeFactory.noMoreInteractions;
 
@@ -49,7 +49,6 @@ import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.stubbing.OngoingStubbingImpl;
 import org.mockito.internal.stubbing.StubberImpl;
 import org.mockito.internal.util.DefaultMockingDetails;
-import org.mockito.internal.util.MockUtil;
 import org.mockito.internal.verification.MockAwareVerificationMode;
 import org.mockito.internal.verification.VerificationDataImpl;
 import org.mockito.internal.verification.VerificationModeFactory;
@@ -85,7 +84,7 @@ public class MockitoCore {
         MockSettingsImpl impl = (MockSettingsImpl) settings;
         MockCreationSettings<T> creationSettings = impl.build(typeToMock);
         checkDoNotMockAnnotation(creationSettings.getTypeToMock(), creationSettings);
-        T mock = createMock(creationSettings);
+        T mock = createMockInstance(creationSettings);
         mockingProgress().mockingStarted(mock, creationSettings);
         return mock;
     }
@@ -131,7 +130,7 @@ public class MockitoCore {
         }
         MockSettingsImpl impl = MockSettingsImpl.class.cast(settings);
         MockCreationSettings<T> creationSettings = impl.buildStatic(classToMock);
-        MockMaker.StaticMockControl<T> control = createStaticMock(classToMock, creationSettings);
+        MockMaker.StaticMockControl<T> control = createStaticClassMock(classToMock, creationSettings);
         control.enable();
         mockingProgress().mockingStarted(classToMock, creationSettings);
         return new MockedStaticImpl<>(control);
@@ -163,7 +162,7 @@ public class MockitoCore {
                     return impl.build(typeToMock);
                 };
         MockMaker.ConstructionMockControl<T> control =
-                createConstructionMock(typeToMock, creationSettings, mockInitializer);
+                createMockedConstruction(typeToMock, creationSettings, mockInitializer);
         control.enable();
         return new MockedConstructionImpl<>(control);
     }
@@ -211,7 +210,7 @@ public class MockitoCore {
         mockingProgress.resetOngoingStubbing();
 
         for (T m : mocks) {
-            resetMock(m);
+            resetMockHandler(m);
         }
     }
 
@@ -347,6 +346,6 @@ public class MockitoCore {
     }
 
     public void clearAllCaches() {
-        MockUtil.clearAllCaches();
+        MockUtilities.clearCaches();
     }
 }
diff --git a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
index cd5194258..fb626bec5 100644
--- a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
+++ b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
@@ -23,7 +23,7 @@ import org.mockito.Mockito;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.plugins.AnnotationEngine;
 import org.mockito.plugins.MemberAccessor;
 
@@ -59,7 +59,7 @@ public class SpyAnnotationEngine implements AnnotationEngine {
                 Object instance;
                 try {
                     instance = accessor.get(field, testInstance);
-                    if (MockUtil.isMock(instance)) {
+                    if (MockUtilities.isMock(instance)) {
                         // instance has been spied earlier
                         // for example happens when MockitoAnnotations.openMocks is called two
                         // times.
diff --git a/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java b/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
index bbfe88b85..b42367783 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
@@ -13,7 +13,7 @@ import org.mockito.Mockito;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.util.reflection.FieldReader;
 import org.mockito.plugins.MemberAccessor;
 
@@ -37,7 +37,7 @@ public class SpyOnInjectedFieldsHandler extends MockInjectionStrategy {
         if (!fieldReader.isNull() && field.isAnnotationPresent(Spy.class)) {
             try {
                 Object instance = fieldReader.read();
-                if (MockUtil.isMock(instance)) {
+                if (MockUtilities.isMock(instance)) {
                     // A. instance has been spied earlier
                     // B. protect against multiple use of MockitoAnnotations.openMocks()
                     Mockito.reset(instance);
diff --git a/src/main/java/org/mockito/internal/configuration/injection/filter/NameBasedCandidateFilter.java b/src/main/java/org/mockito/internal/configuration/injection/filter/NameBasedCandidateFilter.java
index b2cc6c75d..34f9f6d79 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/filter/NameBasedCandidateFilter.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/filter/NameBasedCandidateFilter.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.configuration.injection.filter;
 
-import static org.mockito.internal.util.MockUtil.getMockName;
+import static org.mockito.internal.MockUtilities.getMockName;
 
 import java.lang.reflect.Field;
 import java.util.ArrayList;
diff --git a/src/main/java/org/mockito/internal/configuration/injection/filter/TypeBasedCandidateFilter.java b/src/main/java/org/mockito/internal/configuration/injection/filter/TypeBasedCandidateFilter.java
index a62ee4053..5b2090889 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/filter/TypeBasedCandidateFilter.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/filter/TypeBasedCandidateFilter.java
@@ -17,7 +17,7 @@ import java.util.Collection;
 import java.util.List;
 import java.util.stream.Stream;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 
 public class TypeBasedCandidateFilter implements MockCandidateFilter {
 
@@ -159,7 +159,7 @@ public class TypeBasedCandidateFilter implements MockCandidateFilter {
         List<Object> mockTypeMatches = new ArrayList<>();
         for (Object mock : mocks) {
             if (candidateFieldToBeInjected.getType().isAssignableFrom(mock.getClass())) {
-                Type mockType = MockUtil.getMockSettings(mock).getGenericTypeToMock();
+                Type mockType = MockUtilities.getMockSettings(mock).getGenericTypeToMock();
                 Type typeToMock = candidateFieldToBeInjected.getGenericType();
                 boolean bothHaveTypeInfo = typeToMock != null && mockType != null;
                 if (bothHaveTypeInfo) {
diff --git a/src/main/java/org/mockito/internal/configuration/injection/scanner/MockScanner.java b/src/main/java/org/mockito/internal/configuration/injection/scanner/MockScanner.java
index 97984444c..2a3820323 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/scanner/MockScanner.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/scanner/MockScanner.java
@@ -11,7 +11,7 @@ import java.util.Set;
 
 import org.mockito.Mock;
 import org.mockito.Spy;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.util.reflection.FieldReader;
 
 /**
@@ -69,7 +69,7 @@ public class MockScanner {
             return instance;
         }
         if (isMockOrSpy(instance)) {
-            MockUtil.maybeRedefineMockName(instance, field.getName());
+            MockUtilities.redefineMockNameIfDefault(instance, field.getName());
             return instance;
         }
         return null;
@@ -80,6 +80,6 @@ public class MockScanner {
     }
 
     private boolean isMockOrSpy(Object instance) {
-        return MockUtil.isMock(instance) || MockUtil.isSpy(instance);
+        return MockUtilities.isMock(instance) || MockUtilities.isSpy(instance);
     }
 }
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java b/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginRegistry.java
similarity index 54%
rename from src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
rename to src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginRegistry.java
index 365c350e9..4ed5685f4 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginRegistry.java
@@ -16,80 +16,85 @@ import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockitoLogger;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.infra.MockitoPluginRegistry;
 import org.mockito.plugins.PluginSwitch;
 import org.mockito.plugins.StackTraceCleanerProvider;
 
-public class DefaultMockitoPlugins implements MockitoPlugins {
+public class DefaultMockitoPluginRegistry implements MockitoPluginRegistry {
 
-    private static final Map<String, String> DEFAULT_PLUGINS = new HashMap<>();
-    static final String INLINE_ALIAS = MockMakers.INLINE;
-    static final String PROXY_ALIAS = MockMakers.PROXY;
-    static final String SUBCLASS_ALIAS = MockMakers.SUBCLASS;
+    private static final Map<String, String> BUILTIN_PLUGIN_MAP = new HashMap<>();
+    static final String EMBEDDED_ALIAS = MockMakers.INLINE;
+    static final String PROXY_IDENTIFIER = MockMakers.PROXY;
+    static final String DERIVED_ALIAS = MockMakers.SUBCLASS;
     public static final Set<String> MOCK_MAKER_ALIASES = new HashSet<>();
-    static final String MODULE_ALIAS = "member-accessor-module";
-    static final String REFLECTION_ALIAS = "member-accessor-reflection";
+    static final String MODULE_IDENTIFIER = "member-accessor-module";
+    static final String REFLECTIVE_ALIAS = "member-accessor-reflection";
     public static final Set<String> MEMBER_ACCESSOR_ALIASES = new HashSet<>();
 
     static {
         // Keep the mapping: plugin interface name -> plugin implementation class name
-        DEFAULT_PLUGINS.put(PluginSwitch.class.getName(), DefaultPluginSwitch.class.getName());
-        DEFAULT_PLUGINS.put(
+        BUILTIN_PLUGIN_MAP.put(PluginSwitch.class.getName(), DefaultPluginSwitch.class.getName());
+        BUILTIN_PLUGIN_MAP.put(
                 MockMaker.class.getName(),
                 "org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker");
-        DEFAULT_PLUGINS.put(
+        BUILTIN_PLUGIN_MAP.put(
                 StackTraceCleanerProvider.class.getName(),
                 "org.mockito.internal.exceptions.stacktrace.DefaultStackTraceCleanerProvider");
-        DEFAULT_PLUGINS.put(
+        BUILTIN_PLUGIN_MAP.put(
                 InstantiatorProvider2.class.getName(),
                 "org.mockito.internal.creation.instance.DefaultInstantiatorProvider");
-        DEFAULT_PLUGINS.put(
+        BUILTIN_PLUGIN_MAP.put(
                 AnnotationEngine.class.getName(),
                 "org.mockito.internal.configuration.InjectingAnnotationEngine");
-        DEFAULT_PLUGINS.put(
-                INLINE_ALIAS, "org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker");
-        DEFAULT_PLUGINS.put(PROXY_ALIAS, "org.mockito.internal.creation.proxy.ProxyMockMaker");
-        DEFAULT_PLUGINS.put(
-                SUBCLASS_ALIAS, "org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker");
-        DEFAULT_PLUGINS.put(
+        BUILTIN_PLUGIN_MAP.put(
+            EMBEDDED_ALIAS, "org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker");
+        BUILTIN_PLUGIN_MAP.put(PROXY_IDENTIFIER, "org.mockito.internal.creation.proxy.ProxyMockMaker");
+        BUILTIN_PLUGIN_MAP.put(
+            DERIVED_ALIAS, "org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker");
+        BUILTIN_PLUGIN_MAP.put(
                 MockitoLogger.class.getName(), "org.mockito.internal.util.ConsoleMockitoLogger");
-        DEFAULT_PLUGINS.put(
+        BUILTIN_PLUGIN_MAP.put(
                 MemberAccessor.class.getName(),
                 "org.mockito.internal.util.reflection.ModuleMemberAccessor");
-        DEFAULT_PLUGINS.put(
-                MODULE_ALIAS, "org.mockito.internal.util.reflection.ModuleMemberAccessor");
-        DEFAULT_PLUGINS.put(
-                REFLECTION_ALIAS, "org.mockito.internal.util.reflection.ReflectionMemberAccessor");
-        DEFAULT_PLUGINS.put(
+        BUILTIN_PLUGIN_MAP.put(
+            MODULE_IDENTIFIER, "org.mockito.internal.util.reflection.ModuleMemberAccessor");
+        BUILTIN_PLUGIN_MAP.put(
+            REFLECTIVE_ALIAS, "org.mockito.internal.util.reflection.ReflectionMemberAccessor");
+        BUILTIN_PLUGIN_MAP.put(
                 DoNotMockEnforcer.class.getName(),
                 "org.mockito.internal.configuration.DefaultDoNotMockEnforcer");
 
-        MOCK_MAKER_ALIASES.add(INLINE_ALIAS);
-        MOCK_MAKER_ALIASES.add(PROXY_ALIAS);
-        MOCK_MAKER_ALIASES.add(SUBCLASS_ALIAS);
+        MOCK_MAKER_ALIASES.add(EMBEDDED_ALIAS);
+        MOCK_MAKER_ALIASES.add(PROXY_IDENTIFIER);
+        MOCK_MAKER_ALIASES.add(DERIVED_ALIAS);
 
-        MEMBER_ACCESSOR_ALIASES.add(MODULE_ALIAS);
-        MEMBER_ACCESSOR_ALIASES.add(REFLECTION_ALIAS);
+        MEMBER_ACCESSOR_ALIASES.add(MODULE_IDENTIFIER);
+        MEMBER_ACCESSOR_ALIASES.add(REFLECTIVE_ALIAS);
     }
 
     @Override
-    public <T> T getDefaultPlugin(Class<T> pluginType) {
-        String className = DEFAULT_PLUGINS.get(pluginType.getName());
-        return create(pluginType, className);
+    public MockMaker getInlineMockMaker() {
+        return createDefaultImplementation(MockMaker.class, BUILTIN_PLUGIN_MAP.get(EMBEDDED_ALIAS));
+    }
+
+    public static String getDefaultPluginClass(String nameOrAlias) {
+        return BUILTIN_PLUGIN_MAP.get(nameOrAlias);
     }
 
-    public static String getDefaultPluginClass(String classOrAlias) {
-        return DEFAULT_PLUGINS.get(classOrAlias);
+    @Override
+    public <T> T getDefaultPlugin(Class<T> pluginClass) {
+        String implementationClass = BUILTIN_PLUGIN_MAP.get(pluginClass.getName());
+        return createDefaultImplementation(pluginClass, implementationClass);
     }
 
     /**
      * Creates an instance of given plugin type, using specific implementation class.
      */
-    private <T> T create(Class<T> pluginType, String className) {
-        if (className == null) {
+    private <T> T createDefaultImplementation(Class<T> pluginClass, String implementationClass) {
+        if (implementationClass == null) {
             throw new IllegalStateException(
                     "No default implementation for requested Mockito plugin type: "
-                            + pluginType.getName()
+                            + pluginClass.getName()
                             + "\n"
                             + "Is this a valid Mockito plugin type? If yes, please report this problem to Mockito team.\n"
                             + "Otherwise, please check if you are passing valid plugin type.\n"
@@ -99,19 +104,14 @@ public class DefaultMockitoPlugins implements MockitoPlugins {
             // Default implementation. Use our own ClassLoader instead of the context
             // ClassLoader, as the default implementation is assumed to be part of
             // Mockito and may not be available via the context ClassLoader.
-            return pluginType.cast(Class.forName(className).getDeclaredConstructor().newInstance());
-        } catch (Exception e) {
+            return pluginClass.cast(Class.forName(implementationClass).getDeclaredConstructor().newInstance());
+        } catch (Exception exception) {
             throw new IllegalStateException(
                     "Internal problem occurred, please report it. "
                             + "Mockito is unable to load the default implementation of class that is a part of Mockito distribution. "
                             + "Failed to load "
-                            + pluginType,
-                    e);
+                            + pluginClass,
+                exception);
         }
     }
-
-    @Override
-    public MockMaker getInlineMockMaker() {
-        return create(MockMaker.class, DEFAULT_PLUGINS.get(INLINE_ALIAS));
-    }
 }
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/PluginInitializer.java b/src/main/java/org/mockito/internal/configuration/plugins/PluginInitializer.java
index b042a8439..d63699512 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/PluginInitializer.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/PluginInitializer.java
@@ -45,7 +45,7 @@ class PluginInitializer {
                     new PluginFinder(pluginSwitch).findPluginClass(Iterables.toIterable(resources));
             if (classOrAlias != null) {
                 if (alias.contains(classOrAlias)) {
-                    classOrAlias = DefaultMockitoPlugins.getDefaultPluginClass(classOrAlias);
+                    classOrAlias = DefaultMockitoPluginRegistry.getDefaultPluginClass(classOrAlias);
                 }
                 Class<?> pluginClass = loader.loadClass(classOrAlias);
                 Object plugin = pluginClass.getDeclaredConstructor().newInstance();
@@ -77,7 +77,7 @@ class PluginInitializer {
             List<T> impls = new ArrayList<>();
             for (String classOrAlias : classesOrAliases) {
                 if (alias.contains(classOrAlias)) {
-                    classOrAlias = DefaultMockitoPlugins.getDefaultPluginClass(classOrAlias);
+                    classOrAlias = DefaultMockitoPluginRegistry.getDefaultPluginClass(classOrAlias);
                 }
                 Class<?> pluginClass = loader.loadClass(classOrAlias);
                 Object plugin = pluginClass.getDeclaredConstructor().newInstance();
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/PluginLoader.java b/src/main/java/org/mockito/internal/configuration/plugins/PluginLoader.java
index e55417332..842d92795 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/PluginLoader.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/PluginLoader.java
@@ -16,17 +16,17 @@ import org.mockito.plugins.PluginSwitch;
 
 class PluginLoader {
 
-    private final DefaultMockitoPlugins plugins;
+    private final DefaultMockitoPluginRegistry plugins;
     private final PluginInitializer initializer;
 
-    PluginLoader(DefaultMockitoPlugins plugins, PluginInitializer initializer) {
+    PluginLoader(DefaultMockitoPluginRegistry plugins, PluginInitializer initializer) {
         this.plugins = plugins;
         this.initializer = initializer;
     }
 
     PluginLoader(PluginSwitch pluginSwitch) {
         this(
-                new DefaultMockitoPlugins(),
+                new DefaultMockitoPluginRegistry(),
                 new PluginInitializer(pluginSwitch, Collections.emptySet()));
     }
 
@@ -38,7 +38,7 @@ class PluginLoader {
      */
     PluginLoader(PluginSwitch pluginSwitch, String... alias) {
         this(
-                new DefaultMockitoPlugins(),
+                new DefaultMockitoPluginRegistry(),
                 new PluginInitializer(pluginSwitch, new HashSet<>(Arrays.asList(alias))));
     }
 
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java b/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java
index 72f5d8e7d..c28047a76 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java
@@ -23,13 +23,13 @@ class PluginRegistry {
     private final MockMaker mockMaker =
             new PluginLoader(
                             pluginSwitch,
-                            DefaultMockitoPlugins.MOCK_MAKER_ALIASES.toArray(new String[0]))
+                            DefaultMockitoPluginRegistry.MOCK_MAKER_ALIASES.toArray(new String[0]))
                     .loadPlugin(MockMaker.class);
 
     private final MemberAccessor memberAccessor =
             new PluginLoader(
                             pluginSwitch,
-                            DefaultMockitoPlugins.MEMBER_ACCESSOR_ALIASES.toArray(new String[0]))
+                            DefaultMockitoPluginRegistry.MEMBER_ACCESSOR_ALIASES.toArray(new String[0]))
                     .loadPlugin(MemberAccessor.class);
 
     private final StackTraceCleanerProvider stackTraceCleanerProvider =
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java b/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
index 20f6dc7bc..518bd6834 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
@@ -13,7 +13,7 @@ import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockResolver;
 import org.mockito.plugins.MockitoLogger;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.infra.MockitoPluginRegistry;
 import org.mockito.plugins.StackTraceCleanerProvider;
 
 /** Access to Mockito behavior that can be reconfigured by plugins */
@@ -91,8 +91,8 @@ public final class Plugins {
     /**
      * @return instance of mockito plugins type
      */
-    public static MockitoPlugins getPlugins() {
-        return new DefaultMockitoPlugins();
+    public static MockitoPluginRegistry getPlugins() {
+        return new DefaultMockitoPluginRegistry();
     }
 
     /**
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
index a1eed21e7..0ce801da2 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
@@ -24,7 +24,7 @@ import java.util.concurrent.locks.ReentrantLock;
 import org.mockito.exceptions.base.MockitoSerializationIssue;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.creation.settings.CreationSettings;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.mock.MockCreationSettings;
 import org.mockito.mock.MockName;
 import org.mockito.mock.SerializableMode;
@@ -119,9 +119,9 @@ class ByteBuddyCrossClassLoaderSerializationSupport implements Serializable {
 
             return new CrossClassLoaderSerializationProxy(mockitoMock);
         } catch (IOException ioe) {
-            MockName mockName = MockUtil.getMockName(mockitoMock);
+            MockName mockName = MockUtilities.getMockName(mockitoMock);
             String mockedType =
-                    MockUtil.getMockSettings(mockitoMock).getTypeToMock().getCanonicalName();
+                    MockUtilities.getMockSettings(mockitoMock).getTypeToMock().getCanonicalName();
             throw new MockitoSerializationIssue(
                     join(
                             "The mock '" + mockName + "' of type '" + mockedType + "'",
@@ -185,7 +185,7 @@ class ByteBuddyCrossClassLoaderSerializationSupport implements Serializable {
             objectOutputStream.close();
             out.close();
 
-            MockCreationSettings<?> mockSettings = MockUtil.getMockSettings(mockitoMock);
+            MockCreationSettings<?> mockSettings = MockUtilities.getMockSettings(mockitoMock);
             this.serializedMock = out.toByteArray();
             this.typeToMock = mockSettings.getTypeToMock();
             this.extraInterfaces = mockSettings.getExtraInterfaces();
diff --git a/src/main/java/org/mockito/internal/exceptions/Reporter.java b/src/main/java/org/mockito/internal/exceptions/Reporter.java
index 060916846..50955bb46 100644
--- a/src/main/java/org/mockito/internal/exceptions/Reporter.java
+++ b/src/main/java/org/mockito/internal/exceptions/Reporter.java
@@ -46,7 +46,7 @@ import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.exceptions.util.ScenarioPrinter;
 import org.mockito.internal.junit.ExceptionFactory;
 import org.mockito.internal.matchers.LocalizedMatcher;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.verification.argumentmatching.ArgumentMatchingTool;
 import org.mockito.invocation.DescribedInvocation;
 import org.mockito.invocation.Invocation;
@@ -308,7 +308,7 @@ public class Reporter {
         return new CannotVerifyStubOnlyMock(
                 join(
                         "Argument \""
-                                + MockUtil.getMockName(mock)
+                                + MockUtilities.getMockName(mock)
                                 + "\" passed to verify is a stubOnly() mock which cannot be verified.",
                         "If you intend to verify invocations on this mock, don't use stubOnly() in its MockSettings."));
     }
@@ -552,7 +552,7 @@ public class Reporter {
                         "No interactions wanted here:",
                         LocationFactory.create(),
                         "But found this interaction on mock '"
-                                + MockUtil.getMockName(undesired.getMock())
+                                + MockUtilities.getMockName(undesired.getMock())
                                 + "':",
                         undesired.getLocation(),
                         scenario));
@@ -564,7 +564,7 @@ public class Reporter {
                         "No interactions wanted here:",
                         LocationFactory.create(),
                         "But found this interaction on mock '"
-                                + MockUtil.getMockName(undesired.getMock())
+                                + MockUtilities.getMockName(undesired.getMock())
                                 + "':",
                         undesired.getLocation()));
     }
@@ -583,7 +583,7 @@ public class Reporter {
                         "No interactions wanted here:",
                         LocationFactory.create(),
                         "But found these interactions on mock '"
-                                + MockUtil.getMockName(mock)
+                                + MockUtilities.getMockName(mock)
                                 + "':",
                         join("", locations),
                         scenario));
@@ -656,7 +656,7 @@ public class Reporter {
                         methodName + "() should return " + expectedType,
                         "",
                         "The default answer of "
-                                + MockUtil.getMockName(mock)
+                                + MockUtilities.getMockName(mock)
                                 + " that was configured on the mock is probably incorrectly implemented.",
                         ""));
     }
@@ -884,7 +884,7 @@ public class Reporter {
         return new MockitoException(
                 join(
                         "Mockito couldn't inject mock dependency '"
-                                + MockUtil.getMockName(matchingMock)
+                                + MockUtilities.getMockName(matchingMock)
                                 + "' on field ",
                         "'" + field + "'",
                         "whose type '"
@@ -899,7 +899,7 @@ public class Reporter {
             Field field, Collection<?> mockCandidates) {
         List<String> mockNames =
                 mockCandidates.stream()
-                        .map(MockUtil::getMockName)
+                        .map(MockUtilities::getMockName)
                         .map(MockName::toString)
                         .collect(Collectors.toList());
         return new MockitoException(
@@ -961,7 +961,7 @@ public class Reporter {
                 join(
                         "Invalid argument index for the current invocation of method : ",
                         " -> "
-                                + MockUtil.getMockName(invocation.getMock())
+                                + MockUtilities.getMockName(invocation.getMock())
                                 + "."
                                 + invocation.getMethod().getName()
                                 + "()",
@@ -1014,7 +1014,7 @@ public class Reporter {
                                 + "' cannot be returned because the following ",
                         "method should return the type '" + expectedType + "'",
                         " -> "
-                                + MockUtil.getMockName(invocation.getMock())
+                                + MockUtilities.getMockName(invocation.getMock())
                                 + "."
                                 + invocation.getMethod().getName()
                                 + "()",
@@ -1065,7 +1065,7 @@ public class Reporter {
         return new MockitoException(
                 join(
                         "Methods called on delegated instance must have compatible return types with the mock.",
-                        "When calling: " + mockMethod + " on mock: " + MockUtil.getMockName(mock),
+                        "When calling: " + mockMethod + " on mock: " + MockUtilities.getMockName(mock),
                         "return type should be: "
                                 + mockMethod.getReturnType().getSimpleName()
                                 + ", but was: "
@@ -1081,7 +1081,7 @@ public class Reporter {
         return new MockitoException(
                 join(
                         "Methods called on mock must exist in delegated instance.",
-                        "When calling: " + mockMethod + " on mock: " + MockUtil.getMockName(mock),
+                        "When calling: " + mockMethod + " on mock: " + MockUtilities.getMockName(mock),
                         "no such method was found.",
                         "Check that the instance passed to delegatesTo() is of the correct type or contains compatible methods",
                         "(delegate instance had type: "
diff --git a/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java b/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
index f4a988231..31f732f7d 100644
--- a/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
+++ b/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
@@ -14,7 +14,7 @@ import org.mockito.invocation.InvocationFactory;
 import org.mockito.listeners.MockitoListener;
 import org.mockito.plugins.InlineMockMaker;
 import org.mockito.plugins.MockMaker;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.infra.MockitoPluginRegistry;
 
 public class DefaultMockitoFramework implements MockitoFramework {
 
@@ -33,7 +33,7 @@ public class DefaultMockitoFramework implements MockitoFramework {
     }
 
     @Override
-    public MockitoPlugins getPlugins() {
+    public MockitoPluginRegistry getPlugins() {
         return Plugins.getPlugins();
     }
 
diff --git a/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java b/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
index e58659a16..77d356d59 100644
--- a/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
+++ b/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
@@ -14,7 +14,7 @@ import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.stubbing.OngoingStubbingImpl;
 import org.mockito.internal.stubbing.StubbedInvocationMatcher;
 import org.mockito.internal.stubbing.answers.DefaultAnswerValidator;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.verification.MockAwareVerificationMode;
 import org.mockito.internal.verification.VerificationDataImpl;
 import org.mockito.invocation.Invocation;
@@ -67,7 +67,7 @@ public class MockHandlerImpl<T> implements MockHandler<T> {
         if (verificationMode != null) {
             // We need to check if verification was started on the correct mock
             // - see VerifyingWithAnExtraCallToADifferentMockTest (bug 138)
-            if (MockUtil.areSameMocks(
+            if (MockUtilities.areMocksSame(
                     ((MockAwareVerificationMode) verificationMode).getMock(),
                     invocation.getMock())) {
                 VerificationDataImpl data =
diff --git a/src/main/java/org/mockito/internal/reporting/PrintSettings.java b/src/main/java/org/mockito/internal/reporting/PrintSettings.java
index 41794adcb..dbabc3399 100644
--- a/src/main/java/org/mockito/internal/reporting/PrintSettings.java
+++ b/src/main/java/org/mockito/internal/reporting/PrintSettings.java
@@ -12,7 +12,7 @@ import java.util.Set;
 
 import org.mockito.ArgumentMatcher;
 import org.mockito.internal.matchers.text.MatchersPrinter;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MatchableInvocation;
 
@@ -56,7 +56,7 @@ public class PrintSettings {
     public String print(List<ArgumentMatcher> matchers, Invocation invocation) {
         MatchersPrinter matchersPrinter = new MatchersPrinter();
         String qualifiedName =
-                MockUtil.getMockName(invocation.getMock()) + "." + invocation.getMethod().getName();
+                MockUtilities.getMockName(invocation.getMock()) + "." + invocation.getMethod().getName();
         String invocationString = qualifiedName + matchersPrinter.getArgumentsLine(matchers, this);
         if (isMultiline() || (!matchers.isEmpty() && invocationString.length() > MAX_LINE_LENGTH)) {
             return qualifiedName + matchersPrinter.getArgumentsBlock(matchers, this);
diff --git a/src/main/java/org/mockito/internal/stubbing/StubberImpl.java b/src/main/java/org/mockito/internal/stubbing/StubberImpl.java
index a357de641..5a829cb06 100644
--- a/src/main/java/org/mockito/internal/stubbing/StubberImpl.java
+++ b/src/main/java/org/mockito/internal/stubbing/StubberImpl.java
@@ -9,7 +9,7 @@ import static org.mockito.internal.exceptions.Reporter.notAnException;
 import static org.mockito.internal.exceptions.Reporter.nullPassedToWhenMethod;
 import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
 import static org.mockito.internal.stubbing.answers.DoesNothing.doesNothing;
-import static org.mockito.internal.util.MockUtil.isMock;
+import static org.mockito.internal.MockUtilities.isMock;
 
 import java.util.LinkedList;
 import java.util.List;
@@ -18,7 +18,7 @@ import org.mockito.internal.stubbing.answers.CallsRealMethods;
 import org.mockito.internal.stubbing.answers.Returns;
 import org.mockito.internal.stubbing.answers.ThrowsException;
 import org.mockito.internal.stubbing.answers.ThrowsExceptionForClassType;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Answer;
 import org.mockito.stubbing.Stubber;
@@ -45,7 +45,7 @@ public class StubberImpl implements Stubber {
             throw notAMockPassedToWhenMethod();
         }
 
-        MockUtil.getInvocationContainer(mock).setAnswersForStubbing(answers, strictness);
+        MockUtilities.getInvocationContainer(mock).setAnswersForStubbing(answers, strictness);
 
         return mock;
     }
diff --git a/src/main/java/org/mockito/internal/stubbing/answers/AbstractThrowsException.java b/src/main/java/org/mockito/internal/stubbing/answers/AbstractThrowsException.java
index 6bcca9dc8..d601faf70 100644
--- a/src/main/java/org/mockito/internal/stubbing/answers/AbstractThrowsException.java
+++ b/src/main/java/org/mockito/internal/stubbing/answers/AbstractThrowsException.java
@@ -8,7 +8,7 @@ import static org.mockito.internal.exceptions.Reporter.cannotStubWithNullThrowab
 import static org.mockito.internal.exceptions.Reporter.checkedExceptionInvalid;
 
 import org.mockito.internal.exceptions.stacktrace.ConditionalStackTraceFilter;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.stubbing.Answer;
 import org.mockito.stubbing.ValidableAnswer;
@@ -26,7 +26,7 @@ public abstract class AbstractThrowsException implements Answer<Object>, Validab
             throw new IllegalStateException(
                     "throwable is null: " + "you shall not call #answer if #validateFor fails!");
         }
-        if (MockUtil.isMock(throwable)) {
+        if (MockUtilities.isMock(throwable)) {
             throw throwable;
         }
         Throwable t = throwable.fillInStackTrace();
diff --git a/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java b/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
index c159906af..e88656938 100644
--- a/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
+++ b/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
@@ -11,7 +11,7 @@ import java.util.Arrays;
 import java.util.List;
 
 import org.mockito.internal.invocation.AbstractAwareMethod;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.util.Primitives;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
@@ -91,7 +91,7 @@ public class InvocationInfo implements AbstractAwareMethod {
      */
     public boolean isVoid() {
         final MockCreationSettings mockSettings =
-                MockUtil.getMockHandler(invocation.getMock()).getMockSettings();
+                MockUtilities.getMockHandler(invocation.getMock()).getMockSettings();
         Class<?> returnType =
                 GenericMetadataSupport.inferFrom(mockSettings.getTypeToMock())
                         .resolveGenericReturnType(this.method)
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
index 8b64a1691..06dce23c9 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
@@ -8,7 +8,7 @@ import java.lang.reflect.GenericArrayType;
 import java.lang.reflect.Type;
 import java.lang.reflect.TypeVariable;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.mock.MockCreationSettings;
@@ -36,8 +36,8 @@ final class RetrieveGenericsForDefaultAnswers {
 
         if (type != null) {
             final MockCreationSettings<?> mockSettings =
-                    MockUtil.getMockSettings(invocation.getMock());
-            if (!MockUtil.typeMockabilityOf(type, mockSettings.getMockMaker()).mockable()) {
+                    MockUtilities.getMockSettings(invocation.getMock());
+            if (!MockUtilities.isTypeMockable(type, mockSettings.getMockMaker()).mockable()) {
                 return null;
             }
 
@@ -91,7 +91,7 @@ final class RetrieveGenericsForDefaultAnswers {
             final InvocationOnMock invocation, final TypeVariable returnType) {
         // Class level
         final MockCreationSettings mockSettings =
-                MockUtil.getMockHandler(invocation.getMock()).getMockSettings();
+                MockUtilities.getMockHandler(invocation.getMock()).getMockSettings();
         final GenericMetadataSupport returnTypeSupport =
                 GenericMetadataSupport.inferFrom(mockSettings.getTypeToMock())
                         .resolveGenericReturnType(invocation.getMethod());
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
index 27faed9d9..3594a2fb2 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
@@ -5,7 +5,7 @@
 package org.mockito.internal.stubbing.defaultanswers;
 
 import static org.mockito.Mockito.withSettings;
-import static org.mockito.internal.util.MockUtil.typeMockabilityOf;
+import static org.mockito.internal.MockUtilities.isTypeMockable;
 
 import java.io.IOException;
 import java.io.Serializable;
@@ -16,7 +16,7 @@ import org.mockito.internal.MockitoCore;
 import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.stubbing.StubbedInvocationMatcher;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.mock.MockCreationSettings;
@@ -51,14 +51,14 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
         GenericMetadataSupport returnTypeGenericMetadata =
                 actualParameterizedType(invocation.getMock())
                         .resolveGenericReturnType(invocation.getMethod());
-        MockCreationSettings<?> mockSettings = MockUtil.getMockSettings(invocation.getMock());
+        MockCreationSettings<?> mockSettings = MockUtilities.getMockSettings(invocation.getMock());
 
         Class<?> rawType = returnTypeGenericMetadata.rawType();
         final var emptyValue = ReturnsEmptyValues.returnCommonEmptyValueFor(rawType);
         if (emptyValue != null) {
             return emptyValue;
         }
-        if (!typeMockabilityOf(rawType, mockSettings.getMockMaker()).mockable()) {
+        if (!isTypeMockable(rawType, mockSettings.getMockMaker()).mockable()) {
             if (invocation.getMethod().getReturnType().equals(rawType)) {
                 return delegate().answer(invocation);
             } else {
@@ -83,7 +83,7 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
     private Object deepStub(
             InvocationOnMock invocation, GenericMetadataSupport returnTypeGenericMetadata)
             throws Throwable {
-        InvocationContainerImpl container = MockUtil.getInvocationContainer(invocation.getMock());
+        InvocationContainerImpl container = MockUtilities.getInvocationContainer(invocation.getMock());
 
         Answer existingAnswer = container.findStubbedAnswer();
         if (existingAnswer != null) {
@@ -116,7 +116,7 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
      */
     private Object newDeepStubMock(
             GenericMetadataSupport returnTypeGenericMetadata, Object parentMock) {
-        MockCreationSettings parentMockSettings = MockUtil.getMockSettings(parentMock);
+        MockCreationSettings parentMockSettings = MockUtilities.getMockSettings(parentMock);
         return mockitoCore()
                 .mock(
                         returnTypeGenericMetadata.rawType(),
@@ -155,7 +155,7 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
 
     protected GenericMetadataSupport actualParameterizedType(Object mock) {
         CreationSettings mockSettings =
-                (CreationSettings) MockUtil.getMockHandler(mock).getMockSettings();
+                (CreationSettings) MockUtilities.getMockHandler(mock).getMockSettings();
         return GenericMetadataSupport.inferFrom(mockSettings.getTypeToMock());
     }
 
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsEmptyValues.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsEmptyValues.java
index c2dd0f7b2..d8f1e7973 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsEmptyValues.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsEmptyValues.java
@@ -33,7 +33,7 @@ import java.util.stream.IntStream;
 import java.util.stream.LongStream;
 import java.util.stream.Stream;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.util.Primitives;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.mock.MockName;
@@ -82,10 +82,10 @@ public class ReturnsEmptyValues implements Answer<Object>, Serializable {
     public Object answer(InvocationOnMock invocation) {
         if (isToStringMethod(invocation.getMethod())) {
             Object mock = invocation.getMock();
-            MockName name = MockUtil.getMockName(mock);
+            MockName name = MockUtilities.getMockName(mock);
             if (name.isDefault()) {
                 return "Mock for "
-                        + MockUtil.getMockSettings(mock).getTypeToMock().getSimpleName()
+                        + MockUtilities.getMockSettings(mock).getTypeToMock().getSimpleName()
                         + ", hashCode: "
                         + mock.hashCode();
             } else {
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
index c15578091..f909e9689 100755
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
@@ -8,7 +8,7 @@ import java.io.Serializable;
 
 import org.mockito.Mockito;
 import org.mockito.internal.creation.MockSettingsImpl;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.mock.MockCreationSettings;
 import org.mockito.stubbing.Answer;
@@ -36,7 +36,7 @@ public class ReturnsMocks implements Answer<Object>, Serializable {
                         }
 
                         MockCreationSettings<?> mockSettings =
-                                MockUtil.getMockSettings(invocation.getMock());
+                                MockUtilities.getMockSettings(invocation.getMock());
 
                         return Mockito.mock(
                                 type,
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
index d538784a9..6756579da 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
@@ -15,7 +15,7 @@ import org.mockito.Mockito;
 import org.mockito.internal.creation.MockSettingsImpl;
 import org.mockito.internal.creation.bytebuddy.MockAccess;
 import org.mockito.internal.debugging.LocationFactory;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.invocation.Location;
 import org.mockito.mock.MockCreationSettings;
@@ -63,7 +63,7 @@ public class ReturnsSmartNulls implements Answer<Object>, Serializable {
                         }
 
                         MockCreationSettings<?> mockSettings =
-                                MockUtil.getMockSettings(invocation.getMock());
+                                MockUtilities.getMockSettings(invocation.getMock());
                         Answer<?> defaultAnswer =
                                 new ThrowsSmartNullPointer(invocation, LocationFactory.create());
 
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/TriesToReturnSelf.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/TriesToReturnSelf.java
index f5643c565..ae052a50e 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/TriesToReturnSelf.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/TriesToReturnSelf.java
@@ -6,7 +6,7 @@ package org.mockito.internal.stubbing.defaultanswers;
 
 import java.io.Serializable;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.stubbing.Answer;
 
@@ -18,7 +18,7 @@ public class TriesToReturnSelf implements Answer<Object>, Serializable {
     public Object answer(InvocationOnMock invocation) throws Throwable {
         Class<?> methodReturnType = invocation.getMethod().getReturnType();
         Object mock = invocation.getMock();
-        Class<?> mockType = MockUtil.getMockHandler(mock).getMockSettings().getTypeToMock();
+        Class<?> mockType = MockUtilities.getMockHandler(mock).getMockSettings().getTypeToMock();
 
         if (methodReturnType.isAssignableFrom(mockType) && methodReturnType != Object.class) {
             return invocation.getMock();
diff --git a/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java b/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
index 1ad5a757f..a977d9aa4 100644
--- a/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
+++ b/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
@@ -8,6 +8,7 @@ import java.util.Collection;
 
 import org.mockito.MockingDetails;
 import org.mockito.exceptions.misusing.NotAMockException;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.debugging.InvocationsPrinter;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.invocation.Invocation;
@@ -17,7 +18,7 @@ import org.mockito.stubbing.Stubbing;
 
 /**
  * Class to inspect any object, and identify whether a particular object is either a mock or a spy.  This is
- * a wrapper for {@link org.mockito.internal.util.MockUtil}.
+ * a wrapper for {@link MockUtilities}.
  */
 public class DefaultMockingDetails implements MockingDetails {
 
@@ -29,12 +30,12 @@ public class DefaultMockingDetails implements MockingDetails {
 
     @Override
     public boolean isMock() {
-        return MockUtil.isMock(toInspect);
+        return MockUtilities.isMock(toInspect);
     }
 
     @Override
     public boolean isSpy() {
-        return MockUtil.isSpy(toInspect);
+        return MockUtilities.isSpy(toInspect);
     }
 
     @Override
@@ -44,7 +45,7 @@ public class DefaultMockingDetails implements MockingDetails {
 
     private InvocationContainerImpl getInvocationContainer() {
         assertGoodMock();
-        return MockUtil.getInvocationContainer(toInspect);
+        return MockUtilities.getInvocationContainer(toInspect);
     }
 
     @Override
@@ -75,7 +76,7 @@ public class DefaultMockingDetails implements MockingDetails {
 
     private MockHandler<?> mockHandler() {
         assertGoodMock();
-        return MockUtil.getMockHandler(toInspect);
+        return MockUtilities.getMockHandler(toInspect);
     }
 
     private void assertGoodMock() {
diff --git a/src/main/java/org/mockito/internal/util/MockCreationValidator.java b/src/main/java/org/mockito/internal/util/MockCreationValidator.java
index 9db6b36ea..63d804492 100644
--- a/src/main/java/org/mockito/internal/util/MockCreationValidator.java
+++ b/src/main/java/org/mockito/internal/util/MockCreationValidator.java
@@ -12,6 +12,7 @@ import static org.mockito.internal.exceptions.Reporter.usingConstructorWithFancy
 
 import java.util.Collection;
 
+import org.mockito.internal.MockUtilities;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker.TypeMockability;
 
@@ -19,7 +20,7 @@ import org.mockito.plugins.MockMaker.TypeMockability;
 public class MockCreationValidator {
 
     public void validateType(Class<?> classToMock, String mockMaker) {
-        TypeMockability typeMockability = MockUtil.typeMockabilityOf(classToMock, mockMaker);
+        TypeMockability typeMockability = MockUtilities.isTypeMockable(classToMock, mockMaker);
         if (!typeMockability.mockable()) {
             throw cannotMockClass(classToMock, typeMockability.nonMockableReason());
         }
diff --git a/src/main/java/org/mockito/internal/util/MockUtil.java b/src/main/java/org/mockito/internal/util/MockUtil.java
deleted file mode 100644
index 0d80f6e19..000000000
--- a/src/main/java/org/mockito/internal/util/MockUtil.java
+++ /dev/null
@@ -1,220 +0,0 @@
-/*
- * Copyright (c) 2007 Mockito contributors
- * This program is made available under the terms of the MIT License.
- */
-package org.mockito.internal.util;
-
-import org.mockito.MockedConstruction;
-import org.mockito.Mockito;
-import org.mockito.exceptions.misusing.NotAMockException;
-import org.mockito.internal.configuration.plugins.DefaultMockitoPlugins;
-import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.creation.settings.CreationSettings;
-import org.mockito.internal.stubbing.InvocationContainerImpl;
-import org.mockito.internal.util.reflection.LenientCopyTool;
-import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
-import org.mockito.mock.MockName;
-import org.mockito.plugins.MockMaker;
-import org.mockito.plugins.MockMaker.TypeMockability;
-import org.mockito.plugins.MockResolver;
-
-import java.util.Collections;
-import java.util.Map;
-import java.util.concurrent.ConcurrentHashMap;
-import java.util.function.Function;
-
-import static org.mockito.internal.handler.MockHandlerFactory.createMockHandler;
-
-@SuppressWarnings("unchecked")
-public class MockUtil {
-
-    private static final MockMaker defaultMockMaker = Plugins.getMockMaker();
-    private static final Map<Class<? extends MockMaker>, MockMaker> mockMakers =
-            new ConcurrentHashMap<>(
-                    Collections.singletonMap(defaultMockMaker.getClass(), defaultMockMaker));
-
-    private MockUtil() {}
-
-    private static MockMaker getMockMaker(String mockMaker) {
-        if (mockMaker == null) {
-            return defaultMockMaker;
-        }
-
-        String typeName;
-        if (DefaultMockitoPlugins.MOCK_MAKER_ALIASES.contains(mockMaker)) {
-            typeName = DefaultMockitoPlugins.getDefaultPluginClass(mockMaker);
-        } else {
-            typeName = mockMaker;
-        }
-
-        Class<? extends MockMaker> type;
-        // Using the context class loader because PluginInitializer.loadImpl is using it as well.
-        // Personally, I am suspicious whether the context class loader is a good choice in either
-        // of these cases.
-        ClassLoader loader = Thread.currentThread().getContextClassLoader();
-        if (loader == null) {
-            loader = ClassLoader.getSystemClassLoader();
-        }
-        try {
-            type = loader.loadClass(typeName).asSubclass(MockMaker.class);
-        } catch (Exception e) {
-            throw new IllegalStateException("Failed to load MockMaker: " + mockMaker, e);
-        }
-
-        return mockMakers.computeIfAbsent(
-                type,
-                t -> {
-                    try {
-                        return t.getDeclaredConstructor().newInstance();
-                    } catch (Exception e) {
-                        throw new IllegalStateException(
-                                "Failed to construct MockMaker: " + t.getName(), e);
-                    }
-                });
-    }
-
-    public static TypeMockability typeMockabilityOf(Class<?> type, String mockMaker) {
-        return getMockMaker(mockMaker).isTypeMockable(type);
-    }
-
-    public static <T> T createMock(MockCreationSettings<T> settings) {
-        MockMaker mockMaker = getMockMaker(settings.getMockMaker());
-        MockHandler mockHandler = createMockHandler(settings);
-
-        Object spiedInstance = settings.getSpiedInstance();
-
-        T mock;
-        if (spiedInstance != null) {
-            mock =
-                    mockMaker
-                            .createSpy(settings, mockHandler, (T) spiedInstance)
-                            .orElseGet(
-                                    () -> {
-                                        T instance = mockMaker.createMock(settings, mockHandler);
-                                        new LenientCopyTool().copyToMock(spiedInstance, instance);
-                                        return instance;
-                                    });
-        } else {
-            mock = mockMaker.createMock(settings, mockHandler);
-        }
-
-        return mock;
-    }
-
-    public static void resetMock(Object mock) {
-        MockHandler oldHandler = getMockHandler(mock);
-        MockCreationSettings settings = oldHandler.getMockSettings();
-        MockHandler newHandler = createMockHandler(settings);
-
-        mock = resolve(mock);
-        getMockMaker(settings.getMockMaker()).resetMock(mock, newHandler, settings);
-    }
-
-    public static MockHandler<?> getMockHandler(Object mock) {
-        MockHandler handler = getMockHandlerOrNull(mock);
-        if (handler != null) {
-            return handler;
-        } else {
-            throw new NotAMockException("Argument should be a mock, but is: " + mock.getClass());
-        }
-    }
-
-    public static InvocationContainerImpl getInvocationContainer(Object mock) {
-        return (InvocationContainerImpl) getMockHandler(mock).getInvocationContainer();
-    }
-
-    public static boolean isSpy(Object mock) {
-        return isMock(mock)
-                && getMockSettings(mock).getDefaultAnswer() == Mockito.CALLS_REAL_METHODS;
-    }
-
-    public static boolean isMock(Object mock) {
-        // TODO SF (perf tweak) in our codebase we call mockMaker.getHandler() multiple times
-        // unnecessarily
-        // This is not ideal because getHandler() can be expensive (reflective calls inside mock
-        // maker)
-        // The frequent pattern in the codebase are separate calls to: 1) isMock(mock) then 2)
-        // getMockHandler(mock)
-        // We could replace it with using mockingDetails().isMock()
-        // Let's refactor the codebase and use new mockingDetails() in all relevant places.
-        // Potentially we could also move other methods to MockitoMock, some other candidates:
-        // getInvocationContainer, isSpy, etc.
-        // This also allows us to reuse our public API MockingDetails
-        if (mock == null) {
-            return false;
-        }
-        return getMockHandlerOrNull(mock) != null;
-    }
-
-    private static MockHandler<?> getMockHandlerOrNull(Object mock) {
-        if (mock == null) {
-            throw new NotAMockException("Argument should be a mock, but is null!");
-        }
-
-        mock = resolve(mock);
-
-        for (MockMaker mockMaker : mockMakers.values()) {
-            MockHandler<?> handler = mockMaker.getHandler(mock);
-            if (handler != null) {
-                assert getMockMaker(handler.getMockSettings().getMockMaker()) == mockMaker;
-                return handler;
-            }
-        }
-        return null;
-    }
-
-    private static Object resolve(Object mock) {
-        if (mock instanceof Class<?>) { // static mocks are resolved by definition
-            return mock;
-        }
-        for (MockResolver mockResolver : Plugins.getMockResolvers()) {
-            mock = mockResolver.resolve(mock);
-        }
-        return mock;
-    }
-
-    public static boolean areSameMocks(Object mockA, Object mockB) {
-        return mockA == mockB || resolve(mockA) == resolve(mockB);
-    }
-
-    public static MockName getMockName(Object mock) {
-        return getMockHandler(mock).getMockSettings().getMockName();
-    }
-
-    public static void maybeRedefineMockName(Object mock, String newName) {
-        MockName mockName = getMockName(mock);
-        // TODO SF hacky...
-        MockCreationSettings mockSettings = getMockHandler(mock).getMockSettings();
-        if (mockName.isDefault() && mockSettings instanceof CreationSettings) {
-            ((CreationSettings) mockSettings).setMockName(new MockNameImpl(newName));
-        }
-    }
-
-    public static MockCreationSettings getMockSettings(Object mock) {
-        return getMockHandler(mock).getMockSettings();
-    }
-
-    public static <T> MockMaker.StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings) {
-        MockMaker mockMaker = getMockMaker(settings.getMockMaker());
-        MockHandler<T> handler = createMockHandler(settings);
-        return mockMaker.createStaticMock(type, settings, handler);
-    }
-
-    public static <T> MockMaker.ConstructionMockControl<T> createConstructionMock(
-            Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
-            MockedConstruction.MockInitializer<T> mockInitializer) {
-        Function<MockedConstruction.Context, MockHandler<T>> handlerFactory =
-                context -> createMockHandler(settingsFactory.apply(context));
-        return defaultMockMaker.createConstructionMock(
-                type, settingsFactory, handlerFactory, mockInitializer);
-    }
-
-    public static void clearAllCaches() {
-        for (MockMaker mockMaker : mockMakers.values()) {
-            mockMaker.clearAllCaches();
-        }
-    }
-}
diff --git a/src/main/java/org/mockito/internal/util/collections/HashCodeAndEqualsMockWrapper.java b/src/main/java/org/mockito/internal/util/collections/HashCodeAndEqualsMockWrapper.java
index 50e194db7..1295b7eaf 100644
--- a/src/main/java/org/mockito/internal/util/collections/HashCodeAndEqualsMockWrapper.java
+++ b/src/main/java/org/mockito/internal/util/collections/HashCodeAndEqualsMockWrapper.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.util.collections;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 
 /**
  * hashCode and equals safe mock wrapper.
@@ -63,8 +63,8 @@ public class HashCodeAndEqualsMockWrapper {
     public String toString() {
         return "HashCodeAndEqualsMockWrapper{"
                 + "mockInstance="
-                + (MockUtil.isMock(mockInstance)
-                        ? MockUtil.getMockName(mockInstance)
+                + (MockUtilities.isMock(mockInstance)
+                        ? MockUtilities.getMockName(mockInstance)
                         : typeInstanceString())
                 + '}';
     }
diff --git a/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java b/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
index 7d51a6bb1..0b65f25f1 100644
--- a/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
+++ b/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
@@ -6,7 +6,7 @@ package org.mockito.internal.util.reflection;
 
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.plugins.MemberAccessor;
 
 import java.lang.reflect.Constructor;
@@ -263,7 +263,7 @@ public class FieldInitializer {
                             // Instead of checking for mockability, I think it would be better to
                             // ask the argResolver whether it can resolve this type.
                             // Anyway, I keep it for now to avoid breaking any existing code.
-                            if (MockUtil.typeMockabilityOf(aClass, null).mockable()) {
+                            if (MockUtilities.isTypeMockable(aClass, null).mockable()) {
                                 constructorMockableParamsSize++;
                             }
                         }
diff --git a/src/main/java/org/mockito/plugins/MockitoPlugins.java b/src/main/java/org/mockito/plugins/infra/MockitoPluginRegistry.java
similarity index 86%
rename from src/main/java/org/mockito/plugins/MockitoPlugins.java
rename to src/main/java/org/mockito/plugins/infra/MockitoPluginRegistry.java
index d911077fd..d0825a211 100644
--- a/src/main/java/org/mockito/plugins/MockitoPlugins.java
+++ b/src/main/java/org/mockito/plugins/infra/MockitoPluginRegistry.java
@@ -2,10 +2,11 @@
  * Copyright (c) 2017 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.plugins;
+package org.mockito.plugins.infra;
 
 import org.mockito.Mockito;
 import org.mockito.MockitoFramework;
+import org.mockito.plugins.MockMaker;
 
 /**
  * Instance of this interface is available via {@link MockitoFramework#getPlugins()}.
@@ -17,19 +18,7 @@ import org.mockito.MockitoFramework;
  *
  * @since 2.10.0
  */
-public interface MockitoPlugins {
-
-    /**
-     * Returns the default plugin implementation used by Mockito.
-     * Mockito plugins are stateless so it is recommended to keep hold of the returned plugin implementation
-     * rather than calling this method multiple times.
-     * Each time this method is called, new instance of the plugin is created.
-     *
-     * @param pluginType type of the plugin, for example {@link MockMaker}.
-     * @return the plugin instance
-     * @since 2.10.0
-     */
-    <T> T getDefaultPlugin(Class<T> pluginType);
+public interface MockitoPluginRegistry {
 
     /**
      * Returns inline mock maker, an optional mock maker that is bundled with Mockito distribution.
@@ -41,4 +30,16 @@ public interface MockitoPlugins {
      * @since 2.10.0
      */
     MockMaker getInlineMockMaker();
+
+    /**
+     * Returns the default plugin implementation used by Mockito.
+     * Mockito plugins are stateless so it is recommended to keep hold of the returned plugin implementation
+     * rather than calling this method multiple times.
+     * Each time this method is called, new instance of the plugin is created.
+     *
+     * @param pluginClass type of the plugin, for example {@link MockMaker}.
+     * @return the plugin instance
+     * @since 2.10.0
+     */
+    <T> T getDefaultPlugin(Class<T> pluginClass);
 }
diff --git a/src/test/java/org/mockito/MockitoEnvTest.java b/src/test/java/org/mockito/MockitoEnvTest.java
index 1a162e939..fb6c2118d 100644
--- a/src/test/java/org/mockito/MockitoEnvTest.java
+++ b/src/test/java/org/mockito/MockitoEnvTest.java
@@ -11,7 +11,7 @@ import static org.hamcrest.CoreMatchers.nullValue;
 
 import org.junit.Assume;
 import org.junit.Test;
-import org.mockito.internal.configuration.plugins.DefaultMockitoPlugins;
+import org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
@@ -23,7 +23,7 @@ public class MockitoEnvTest {
         Assume.assumeThat(mockMaker, not(nullValue()));
         Assume.assumeThat(mockMaker, endsWith("default"));
 
-        assertThat(DefaultMockitoPlugins.getDefaultPluginClass(MockMaker.class.getName()))
+        assertThat(DefaultMockitoPluginRegistry.getDefaultPluginClass(MockMaker.class.getName()))
                 .isEqualTo(Plugins.getMockMaker().getClass().getName());
     }
 
@@ -33,7 +33,7 @@ public class MockitoEnvTest {
         Assume.assumeThat(mockMaker, not(nullValue()));
         Assume.assumeThat(mockMaker, not(endsWith("default")));
 
-        assertThat(DefaultMockitoPlugins.getDefaultPluginClass(mockMaker))
+        assertThat(DefaultMockitoPluginRegistry.getDefaultPluginClass(mockMaker))
                 .isEqualTo(Plugins.getMockMaker().getClass().getName());
     }
 
@@ -43,7 +43,7 @@ public class MockitoEnvTest {
         Assume.assumeThat(memberAccessor, not(nullValue()));
         Assume.assumeThat(memberAccessor, endsWith("default"));
 
-        assertThat(DefaultMockitoPlugins.getDefaultPluginClass(MemberAccessor.class.getName()))
+        assertThat(DefaultMockitoPluginRegistry.getDefaultPluginClass(MemberAccessor.class.getName()))
                 .isEqualTo(Plugins.getMemberAccessor().getClass().getName());
     }
 
@@ -53,7 +53,7 @@ public class MockitoEnvTest {
         Assume.assumeThat(memberAccessor, not(nullValue()));
         Assume.assumeThat(memberAccessor, not(endsWith("default")));
 
-        assertThat(DefaultMockitoPlugins.getDefaultPluginClass(memberAccessor))
+        assertThat(DefaultMockitoPluginRegistry.getDefaultPluginClass(memberAccessor))
                 .isEqualTo(Plugins.getMemberAccessor().getClass().getName());
     }
 }
diff --git a/src/test/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginsTest.java b/src/test/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginsTest.java
index 61fc8e8ed..f3a53e7ca 100644
--- a/src/test/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginsTest.java
+++ b/src/test/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginsTest.java
@@ -5,9 +5,9 @@
 package org.mockito.internal.configuration.plugins;
 
 import static org.junit.Assert.*;
-import static org.mockito.internal.configuration.plugins.DefaultMockitoPlugins.INLINE_ALIAS;
-import static org.mockito.internal.configuration.plugins.DefaultMockitoPlugins.PROXY_ALIAS;
-import static org.mockito.internal.configuration.plugins.DefaultMockitoPlugins.SUBCLASS_ALIAS;
+import static org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry.EMBEDDED_ALIAS;
+import static org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry.PROXY_IDENTIFIER;
+import static org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry.DERIVED_ALIAS;
 
 import org.junit.Test;
 import org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker;
@@ -19,20 +19,20 @@ import org.mockitoutil.TestBase;
 
 public class DefaultMockitoPluginsTest extends TestBase {
 
-    private DefaultMockitoPlugins plugins = new DefaultMockitoPlugins();
+    private DefaultMockitoPluginRegistry plugins = new DefaultMockitoPluginRegistry();
 
     @Test
     public void provides_plugins() throws Exception {
         assertEquals(
                 "org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker",
-                DefaultMockitoPlugins.getDefaultPluginClass(INLINE_ALIAS));
+                DefaultMockitoPluginRegistry.getDefaultPluginClass(EMBEDDED_ALIAS));
         assertEquals(InlineByteBuddyMockMaker.class, plugins.getInlineMockMaker().getClass());
         assertEquals(
                 "org.mockito.internal.creation.proxy.ProxyMockMaker",
-                DefaultMockitoPlugins.getDefaultPluginClass(PROXY_ALIAS));
+                DefaultMockitoPluginRegistry.getDefaultPluginClass(PROXY_IDENTIFIER));
         assertEquals(
                 "org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker",
-                DefaultMockitoPlugins.getDefaultPluginClass(SUBCLASS_ALIAS));
+                DefaultMockitoPluginRegistry.getDefaultPluginClass(DERIVED_ALIAS));
         assertEquals(
                 InlineByteBuddyMockMaker.class,
                 plugins.getDefaultPlugin(MockMaker.class).getClass());
diff --git a/src/test/java/org/mockito/internal/configuration/plugins/PluginLoaderTest.java b/src/test/java/org/mockito/internal/configuration/plugins/PluginLoaderTest.java
index 543af6821..6bbf8f169 100644
--- a/src/test/java/org/mockito/internal/configuration/plugins/PluginLoaderTest.java
+++ b/src/test/java/org/mockito/internal/configuration/plugins/PluginLoaderTest.java
@@ -24,7 +24,8 @@ public class PluginLoaderTest {
     @Rule public MockitoRule rule = MockitoJUnit.rule().strictness(Strictness.STRICT_STUBS);
 
     @Mock PluginInitializer initializer;
-    @Mock DefaultMockitoPlugins plugins;
+    @Mock
+    DefaultMockitoPluginRegistry plugins;
     @InjectMocks PluginLoader loader;
 
     @Test
diff --git a/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java b/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
index 3691412e5..a30686f67 100755
--- a/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
+++ b/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
@@ -11,7 +11,7 @@ import static org.mockito.Mockito.when;
 import org.junit.Test;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.stubbing.defaultanswers.ReturnsGenericDeepStubsTest.WithGenerics;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockitoutil.TestBase;
 
 public class ReturnsMocksTest extends TestBase {
@@ -36,13 +36,13 @@ public class ReturnsMocksTest extends TestBase {
     @Test
     public void should_return_mock_value_for_interface() throws Throwable {
         Object interfaceMock = values.answer(invocationOf(AllInterface.class, "getInterface"));
-        assertTrue(MockUtil.isMock(interfaceMock));
+        assertTrue(MockUtilities.isMock(interfaceMock));
     }
 
     @Test
     public void should_return_mock_value_for_class() throws Throwable {
         Object classMock = values.answer(invocationOf(AllInterface.class, "getNormalClass"));
-        assertTrue(MockUtil.isMock(classMock));
+        assertTrue(MockUtilities.isMock(classMock));
     }
 
     @SuppressWarnings("unchecked")
@@ -51,7 +51,7 @@ public class ReturnsMocksTest extends TestBase {
         WithGenerics<String> classMock =
                 (WithGenerics<String>)
                         values.answer(invocationOf(AllInterface.class, "withGenerics"));
-        assertTrue(MockUtil.isMock(classMock));
+        assertTrue(MockUtilities.isMock(classMock));
         when(classMock.execute()).thenReturn("return");
         assertEquals("return", classMock.execute());
     }
diff --git a/src/test/java/org/mockito/internal/util/MockUtilTest.java b/src/test/java/org/mockito/internal/util/MockUtilTest.java
index 834178cde..dfcdb0f1c 100644
--- a/src/test/java/org/mockito/internal/util/MockUtilTest.java
+++ b/src/test/java/org/mockito/internal/util/MockUtilTest.java
@@ -17,6 +17,7 @@ import org.assertj.core.api.Assertions;
 import org.junit.Test;
 import org.mockito.Mockito;
 import org.mockito.exceptions.misusing.NotAMockException;
+import org.mockito.internal.MockUtilities;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockitoutil.TestBase;
 
@@ -26,14 +27,14 @@ public class MockUtilTest extends TestBase {
     @Test
     public void should_get_handler() {
         List<?> mock = Mockito.mock(List.class);
-        assertNotNull(MockUtil.getMockHandler(mock));
+        assertNotNull(MockUtilities.getMockHandler(mock));
     }
 
     @Test
     public void should_scream_when_not_a_mock_passed() {
         assertThatThrownBy(
                         () -> {
-                            MockUtil.getMockHandler("");
+                            MockUtilities.getMockHandler("");
                         })
                 .isInstanceOf(NotAMockException.class)
                 .hasMessage("Argument should be a mock, but is: class java.lang.String");
@@ -43,7 +44,7 @@ public class MockUtilTest extends TestBase {
     public void should_scream_when_null_passed() {
         assertThatThrownBy(
                         () -> {
-                            MockUtil.getMockHandler(null);
+                            MockUtilities.getMockHandler(null);
                         })
                 .isInstanceOf(NotAMockException.class)
                 .hasMessage("Argument should be a mock, but is null!");
@@ -52,25 +53,25 @@ public class MockUtilTest extends TestBase {
     @Test
     public void should_get_mock_settings() {
         List<?> mock = Mockito.mock(List.class);
-        assertNotNull(MockUtil.getMockSettings(mock));
+        assertNotNull(MockUtilities.getMockSettings(mock));
     }
 
     @Test
     public void should_validate_mock() {
-        assertFalse(MockUtil.isMock("i mock a mock"));
-        assertTrue(MockUtil.isMock(Mockito.mock(List.class)));
+        assertFalse(MockUtilities.isMock("i mock a mock"));
+        assertTrue(MockUtilities.isMock(Mockito.mock(List.class)));
     }
 
     @Test
     public void should_validate_spy() {
-        assertFalse(MockUtil.isSpy("i mock a mock"));
-        assertFalse(MockUtil.isSpy(Mockito.mock(List.class)));
-        assertFalse(MockUtil.isSpy(null));
+        assertFalse(MockUtilities.isSpy("i mock a mock"));
+        assertFalse(MockUtilities.isSpy(Mockito.mock(List.class)));
+        assertFalse(MockUtilities.isSpy(null));
 
-        assertTrue(MockUtil.isSpy(Mockito.spy(new ArrayList())));
-        assertTrue(MockUtil.isSpy(Mockito.spy(ArrayList.class)));
+        assertTrue(MockUtilities.isSpy(Mockito.spy(new ArrayList())));
+        assertTrue(MockUtilities.isSpy(Mockito.spy(ArrayList.class)));
         assertTrue(
-                MockUtil.isSpy(
+                MockUtilities.isSpy(
                         Mockito.mock(
                                 ArrayList.class,
                                 withSettings().defaultAnswer(Mockito.CALLS_REAL_METHODS))));
@@ -79,17 +80,17 @@ public class MockUtilTest extends TestBase {
     @Test
     public void should_redefine_MockName_if_default() {
         List<?> mock = Mockito.mock(List.class);
-        MockUtil.maybeRedefineMockName(mock, "newName");
+        MockUtilities.redefineMockNameIfDefault(mock, "newName");
 
-        Assertions.assertThat(MockUtil.getMockName(mock).toString()).isEqualTo("newName");
+        Assertions.assertThat(MockUtilities.getMockName(mock).toString()).isEqualTo("newName");
     }
 
     @Test
     public void should_not_redefine_MockName_if_default() {
         List<?> mock = Mockito.mock(List.class, "original");
-        MockUtil.maybeRedefineMockName(mock, "newName");
+        MockUtilities.redefineMockNameIfDefault(mock, "newName");
 
-        Assertions.assertThat(MockUtil.getMockName(mock).toString()).isEqualTo("original");
+        Assertions.assertThat(MockUtilities.getMockName(mock).toString()).isEqualTo("original");
     }
 
     final class FinalClass {}
@@ -100,12 +101,12 @@ public class MockUtilTest extends TestBase {
 
     @Test
     public void should_know_if_type_is_mockable() throws Exception {
-        Assertions.assertThat(MockUtil.typeMockabilityOf(FinalClass.class, null).mockable())
+        Assertions.assertThat(MockUtilities.isTypeMockable(FinalClass.class, null).mockable())
                 .isEqualTo(Plugins.getMockMaker().isTypeMockable(FinalClass.class).mockable());
 
-        assertFalse(MockUtil.typeMockabilityOf(int.class, null).mockable());
+        assertFalse(MockUtilities.isTypeMockable(int.class, null).mockable());
 
-        assertTrue(MockUtil.typeMockabilityOf(SomeClass.class, null).mockable());
-        assertTrue(MockUtil.typeMockabilityOf(SomeInterface.class, null).mockable());
+        assertTrue(MockUtilities.isTypeMockable(SomeClass.class, null).mockable());
+        assertTrue(MockUtilities.isTypeMockable(SomeInterface.class, null).mockable());
     }
 }
diff --git a/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorIssue421Test.java b/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorIssue421Test.java
index 0e5c67f02..781a5f1f5 100644
--- a/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorIssue421Test.java
+++ b/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorIssue421Test.java
@@ -10,7 +10,7 @@ import org.junit.Test;
 import org.junit.runner.RunWith;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.junit.MockitoJUnitRunner;
 import org.mockitousage.examples.use.ArticleCalculator;
 
@@ -37,7 +37,7 @@ public class MockInjectionUsingConstructorIssue421Test {
         }
 
         public void checkIfMockIsInjected() {
-            assertThat(MockUtil.isMock(calculator)).isTrue();
+            assertThat(MockUtilities.isMock(calculator)).isTrue();
         }
     }
 }
diff --git a/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorTest.java b/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorTest.java
index c45c90ae2..2b8f243da 100644
--- a/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorTest.java
+++ b/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorTest.java
@@ -29,7 +29,7 @@ import org.mockito.Mock;
 import org.mockito.MockitoAnnotations;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.junit.MockitoJUnitRunner;
 import org.mockitousage.IMethods;
 import org.mockitousage.examples.use.ArticleCalculator;
@@ -86,8 +86,8 @@ public class MockInjectionUsingConstructorTest {
 
     @Test
     public void objects_created_with_constructor_initialization_can_be_spied() throws Exception {
-        assertFalse(MockUtil.isMock(articleManager));
-        assertTrue(MockUtil.isMock(spiedArticleManager));
+        assertFalse(MockUtilities.isMock(articleManager));
+        assertTrue(MockUtilities.isMock(spiedArticleManager));
     }
 
     @Test
diff --git a/src/test/java/org/mockitousage/annotation/MockInjectionUsingSetterOrPropertyTest.java b/src/test/java/org/mockitousage/annotation/MockInjectionUsingSetterOrPropertyTest.java
index 0d2af98d6..b76e08dc2 100644
--- a/src/test/java/org/mockitousage/annotation/MockInjectionUsingSetterOrPropertyTest.java
+++ b/src/test/java/org/mockitousage/annotation/MockInjectionUsingSetterOrPropertyTest.java
@@ -20,7 +20,7 @@ import org.mockito.Mock;
 import org.mockito.MockitoAnnotations;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockitousage.IMethods;
 import org.mockitoutil.TestBase;
 
@@ -79,14 +79,14 @@ public class MockInjectionUsingSetterOrPropertyTest extends TestBase {
     @Test
     public void should_inject_mocks_in_spy() {
         assertNotNull(initializedSpy.getAList());
-        assertTrue(MockUtil.isMock(initializedSpy));
+        assertTrue(MockUtilities.isMock(initializedSpy));
     }
 
     @Test
     public void should_initialize_spy_if_null_and_inject_mocks() {
         assertNotNull(notInitializedSpy);
         assertNotNull(notInitializedSpy.getAList());
-        assertTrue(MockUtil.isMock(notInitializedSpy));
+        assertTrue(MockUtilities.isMock(notInitializedSpy));
     }
 
     @Test
diff --git a/src/test/java/org/mockitousage/annotation/SpyAnnotationInitializedInBaseClassTest.java b/src/test/java/org/mockitousage/annotation/SpyAnnotationInitializedInBaseClassTest.java
index 60f87913b..ff6d7dc49 100644
--- a/src/test/java/org/mockitousage/annotation/SpyAnnotationInitializedInBaseClassTest.java
+++ b/src/test/java/org/mockitousage/annotation/SpyAnnotationInitializedInBaseClassTest.java
@@ -5,7 +5,7 @@
 package org.mockitousage.annotation;
 
 import static org.junit.Assert.assertTrue;
-import static org.mockito.internal.util.MockUtil.isMock;
+import static org.mockito.internal.MockUtilities.isMock;
 
 import java.util.LinkedList;
 import java.util.List;
@@ -14,7 +14,7 @@ import org.junit.Before;
 import org.junit.Test;
 import org.mockito.MockitoAnnotations;
 import org.mockito.Spy;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockitoutil.TestBase;
 
 @SuppressWarnings("unchecked")
@@ -34,7 +34,7 @@ public class SpyAnnotationInitializedInBaseClassTest extends TestBase {
         // when
         MockitoAnnotations.openMocks(subClass);
         // then
-        assertTrue(MockUtil.isMock(subClass.list));
+        assertTrue(MockUtilities.isMock(subClass.list));
     }
 
     @Before
diff --git a/src/test/java/org/mockitousage/annotation/SpyInjectionTest.java b/src/test/java/org/mockitousage/annotation/SpyInjectionTest.java
index 9961e6ee2..9a547e6fe 100644
--- a/src/test/java/org/mockitousage/annotation/SpyInjectionTest.java
+++ b/src/test/java/org/mockitousage/annotation/SpyInjectionTest.java
@@ -10,7 +10,7 @@ import java.util.List;
 import org.junit.Test;
 import org.mockito.InjectMocks;
 import org.mockito.Spy;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockitoutil.TestBase;
 
 public class SpyInjectionTest extends TestBase {
@@ -28,6 +28,6 @@ public class SpyInjectionTest extends TestBase {
 
     @Test
     public void shouldDoStuff() throws Exception {
-        MockUtil.isMock(hasSpy.spy);
+        MockUtilities.isMock(hasSpy.spy);
     }
 }
diff --git a/src/test/java/org/mockitousage/debugging/VerboseLoggingOfInvocationsOnMockTest.java b/src/test/java/org/mockitousage/debugging/VerboseLoggingOfInvocationsOnMockTest.java
index 6696c12a5..e93aab60e 100644
--- a/src/test/java/org/mockitousage/debugging/VerboseLoggingOfInvocationsOnMockTest.java
+++ b/src/test/java/org/mockitousage/debugging/VerboseLoggingOfInvocationsOnMockTest.java
@@ -17,7 +17,7 @@ import org.junit.Before;
 import org.junit.Test;
 import org.junit.runner.RunWith;
 import org.mockito.Mock;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.junit.MockitoJUnitRunner;
 
 /**
@@ -155,7 +155,7 @@ public class VerboseLoggingOfInvocationsOnMockTest {
     }
 
     private String mockName(Object mock) {
-        return MockUtil.getMockName(mock).toString();
+        return MockUtilities.getMockName(mock).toString();
     }
 
     private static class UnrelatedClass {
diff --git a/src/test/java/org/mockitousage/junitrule/JUnitTestRuleIntegratesWithRuleChainTest.java b/src/test/java/org/mockitousage/junitrule/JUnitTestRuleIntegratesWithRuleChainTest.java
index 498d2bc89..e57ea3653 100644
--- a/src/test/java/org/mockitousage/junitrule/JUnitTestRuleIntegratesWithRuleChainTest.java
+++ b/src/test/java/org/mockitousage/junitrule/JUnitTestRuleIntegratesWithRuleChainTest.java
@@ -16,7 +16,7 @@ import org.junit.runner.JUnitCore;
 import org.junit.runner.Result;
 import org.junit.runners.model.Statement;
 import org.mockito.Mock;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.junit.MockitoJUnit;
 import org.mockito.quality.Strictness;
 import org.mockitousage.IMethods;
@@ -53,7 +53,7 @@ public class JUnitTestRuleIntegratesWithRuleChainTest {
                                         new Statement() {
                                             @Override
                                             public void evaluate() throws Throwable {
-                                                assertThat(MockUtil.isMock(mock)).isTrue();
+                                                assertThat(MockUtilities.isMock(mock)).isTrue();
                                                 called.set(true);
                                                 base.evaluate();
                                             }
@@ -65,7 +65,7 @@ public class JUnitTestRuleIntegratesWithRuleChainTest {
 
         @Test
         public void creates_mocks_in_correct_rulechain_ordering() {
-            assertThat(MockUtil.isMock(mock)).isTrue();
+            assertThat(MockUtilities.isMock(mock)).isTrue();
             assertThat(called.get()).isTrue();
         }
     }
@@ -79,7 +79,7 @@ public class JUnitTestRuleIntegratesWithRuleChainTest {
                                         new Statement() {
                                             @Override
                                             public void evaluate() throws Throwable {
-                                                assertThat(MockUtil.isMock(mock)).isTrue();
+                                                assertThat(MockUtilities.isMock(mock)).isTrue();
                                                 called.set(true);
                                                 base.evaluate();
                                             }
@@ -91,7 +91,7 @@ public class JUnitTestRuleIntegratesWithRuleChainTest {
 
         @Test
         public void creates_mocks_in_correct_rulechain_ordering() {
-            assertThat(MockUtil.isMock(mock)).isTrue();
+            assertThat(MockUtilities.isMock(mock)).isTrue();
             assertThat(called.get()).isTrue();
         }
 
diff --git a/src/test/java/org/mockitousage/plugins/MockitoPluginsTest.java b/src/test/java/org/mockitousage/plugins/MockitoPluginsTest.java
index dd5f390a5..a85ba8c1a 100644
--- a/src/test/java/org/mockitousage/plugins/MockitoPluginsTest.java
+++ b/src/test/java/org/mockitousage/plugins/MockitoPluginsTest.java
@@ -12,14 +12,14 @@ import org.mockito.plugins.AnnotationEngine;
 import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockitoLogger;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.infra.MockitoPluginRegistry;
 import org.mockito.plugins.PluginSwitch;
 import org.mockito.plugins.StackTraceCleanerProvider;
 import org.mockitoutil.TestBase;
 
 public class MockitoPluginsTest extends TestBase {
 
-    private final MockitoPlugins plugins = Mockito.framework().getPlugins();
+    private final MockitoPluginRegistry plugins = Mockito.framework().getPlugins();
 
     @Test
     public void provides_built_in_plugins() {
diff --git a/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java b/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
index 31abe2e61..db0d58bb3 100644
--- a/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
+++ b/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
@@ -11,7 +11,7 @@ import org.junit.jupiter.api.extension.ExtendWith;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
 import org.mockito.Mockito;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.MockUtilities;
 import org.mockito.junit.jupiter.MockitoExtension;
 
 import static org.assertj.core.api.Assertions.assertThat;
@@ -44,7 +44,7 @@ class JunitJupiterTest {
 
     @Test
     void initializes_parameters_with_custom_configuration(@Mock(name = "overriddenName") Function<String, String> localMock) {
-        assertThat(MockUtil.getMockName(localMock).toString()).isEqualTo("overriddenName");
+        assertThat(MockUtilities.getMockName(localMock).toString()).isEqualTo("overriddenName");
     }
 
     @Nested

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

