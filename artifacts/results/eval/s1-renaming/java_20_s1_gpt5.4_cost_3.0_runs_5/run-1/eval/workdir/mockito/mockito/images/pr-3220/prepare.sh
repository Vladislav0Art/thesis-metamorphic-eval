#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout a0214364c36c840b259a4e5a0b656378e47d90df

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/DoNotMock.java b/src/main/java/org/mockito/DoNotMock.java
index fb2de8ecf..d840767cf 100644
--- a/src/main/java/org/mockito/DoNotMock.java
+++ b/src/main/java/org/mockito/DoNotMock.java
@@ -4,6 +4,8 @@
  */
 package org.mockito;
 
+import org.mockito.plugins.DoNotMockChecker;
+
 import static java.lang.annotation.ElementType.TYPE;
 import static java.lang.annotation.RetentionPolicy.RUNTIME;
 
@@ -16,9 +18,9 @@ import java.lang.annotation.Target;
  * <p>When marking a type {@code @DoNotMock}, you should always point to alternative testing
  * solutions such as standard fakes or other testing utilities.
  *
- * Mockito enforces {@code @DoNotMock} with the {@link org.mockito.plugins.DoNotMockEnforcer}.
+ * Mockito enforces {@code @DoNotMock} with the {@link DoNotMockChecker}.
  *
- * If you want to use a custom {@code @DoNotMock} annotation, the {@link org.mockito.plugins.DoNotMockEnforcer}
+ * If you want to use a custom {@code @DoNotMock} annotation, the {@link DoNotMockChecker}
  * will match on annotations with a type ending in "org.mockito.DoNotMock". You can thus place
  * your custom annotation in {@code com.my.package.org.mockito.DoNotMock} and Mockito will enforce
  * that types annotated by {@code @com.my.package.org.mockito.DoNotMock} can not be mocked.
diff --git a/src/main/java/org/mockito/MockSettings.java b/src/main/java/org/mockito/MockSettings.java
index e9c75c3a1..f7b4a1081 100644
--- a/src/main/java/org/mockito/MockSettings.java
+++ b/src/main/java/org/mockito/MockSettings.java
@@ -14,7 +14,7 @@ import org.mockito.invocation.MockHandler;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.listeners.StubbingLookupListener;
 import org.mockito.listeners.VerificationStartedListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 import org.mockito.quality.Strictness;
@@ -328,28 +328,28 @@ public interface MockSettings extends Serializable {
      * Framework integrators can use this method to create instances of creation settings
      * and use them in advanced use cases, for example to create invocations with {@link InvocationFactory},
      * or to implement custom {@link MockHandler}.
-     * Since {@link MockCreationSettings} is {@link NotExtensible}, Mockito public API needs a creation method for this type.
+     * Since {@link MockCreationOptions} is {@link NotExtensible}, Mockito public API needs a creation method for this type.
      *
      * @param typeToMock class to mock
      * @param <T> type to mock
      * @return immutable view of mock settings
      * @since 2.10.0
      */
-    <T> MockCreationSettings<T> build(Class<T> typeToMock);
+    <T> MockCreationOptions<T> build(Class<T> typeToMock);
 
     /**
      * Creates immutable view of mock settings used later by Mockito, for use within a static mocking.
      * Framework integrators can use this method to create instances of creation settings
      * and use them in advanced use cases, for example to create invocations with {@link InvocationFactory},
      * or to implement custom {@link MockHandler}.
-     * Since {@link MockCreationSettings} is {@link NotExtensible}, Mockito public API needs a creation method for this type.
+     * Since {@link MockCreationOptions} is {@link NotExtensible}, Mockito public API needs a creation method for this type.
      *
      * @param classToMock class to mock
      * @param <T> type to mock
      * @return immutable view of mock settings
      * @since 2.10.0
      */
-    <T> MockCreationSettings<T> buildStatic(Class<T> classToMock);
+    <T> MockCreationOptions<T> buildStatic(Class<T> classToMock);
 
     /**
      * @deprecated Use {@link MockSettings#strictness(Strictness)} instead.
diff --git a/src/main/java/org/mockito/MockingDetails.java b/src/main/java/org/mockito/MockingDetails.java
index 37a149100..36caa0dfe 100644
--- a/src/main/java/org/mockito/MockingDetails.java
+++ b/src/main/java/org/mockito/MockingDetails.java
@@ -8,7 +8,7 @@ import java.util.Collection;
 
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.quality.MockitoHint;
 import org.mockito.stubbing.Stubbing;
 
@@ -54,7 +54,7 @@ public interface MockingDetails {
     /**
      * Returns various mock settings provided when the mock was created, for example:
      *  mocked class, mock name (if any), any extra interfaces (if any), etc.
-     * See also {@link MockCreationSettings}.
+     * See also {@link MockCreationOptions}.
      * <p>
      * This method is useful for framework integrators and for certain edge cases.
      * <p>
@@ -63,7 +63,7 @@ public interface MockingDetails {
      * After all, non-mock objects do not have any mock creation settings.
      * @since 2.1.0
      */
-    MockCreationSettings<?> getMockCreationSettings();
+    MockCreationOptions<?> getMockCreationSettings();
 
     /**
      * Returns stubbings declared on this mock object.
diff --git a/src/main/java/org/mockito/Mockito.java b/src/main/java/org/mockito/Mockito.java
index 75ad37e86..fe8fd90d1 100644
--- a/src/main/java/org/mockito/Mockito.java
+++ b/src/main/java/org/mockito/Mockito.java
@@ -6,8 +6,8 @@ package org.mockito;
 
 import org.mockito.exceptions.misusing.PotentialStubbingProblem;
 import org.mockito.exceptions.misusing.UnnecessaryStubbingException;
-import org.mockito.internal.MockitoCore;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.MockitoEngine;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.framework.DefaultMockitoFramework;
 import org.mockito.internal.session.DefaultMockitoSessionBuilder;
 import org.mockito.internal.util.MockUtil;
@@ -1680,7 +1680,7 @@ import java.util.function.Function;
 @SuppressWarnings("unchecked")
 public class Mockito extends ArgumentMatchers {
 
-    static final MockitoCore MOCKITO_CORE = new MockitoCore();
+    static final MockitoEngine MOCKITO_CORE = new MockitoEngine();
 
     /**
      * The default <code>Answer</code> of every mock <b>if</b> the mock was not stubbed.
@@ -2051,7 +2051,7 @@ public class Mockito extends ArgumentMatchers {
      * @since 1.9.5
      */
     public static MockingDetails mockingDetails(Object toInspect) {
-        return MOCKITO_CORE.mockingDetails(toInspect);
+        return MOCKITO_CORE.getMockingDetails(toInspect);
     }
 
     /**
@@ -2101,7 +2101,7 @@ public class Mockito extends ArgumentMatchers {
      * @return mock object
      */
     public static <T> T mock(Class<T> classToMock, MockSettings mockSettings) {
-        return MOCKITO_CORE.mock(classToMock, mockSettings);
+        return MOCKITO_CORE.createMock(classToMock, mockSettings);
     }
 
     /**
@@ -2188,7 +2188,7 @@ public class Mockito extends ArgumentMatchers {
             throw new IllegalArgumentException(
                     "Please don't pass mock here. Spy is not allowed on mock.");
         }
-        return MOCKITO_CORE.mock(
+        return MOCKITO_CORE.createMock(
                 (Class<T>) object.getClass(),
                 withSettings().spiedInstance(object).defaultAnswer(CALLS_REAL_METHODS));
     }
@@ -2221,7 +2221,7 @@ public class Mockito extends ArgumentMatchers {
      * @since 1.10.12
      */
     public static <T> T spy(Class<T> classToSpy) {
-        return MOCKITO_CORE.mock(
+        return MOCKITO_CORE.createMock(
                 classToSpy, withSettings().useConstructor().defaultAnswer(CALLS_REAL_METHODS));
     }
 
@@ -2325,7 +2325,7 @@ public class Mockito extends ArgumentMatchers {
      * @return mock controller
      */
     public static <T> MockedStatic<T> mockStatic(Class<T> classToMock, MockSettings mockSettings) {
-        return MOCKITO_CORE.mockStatic(classToMock, mockSettings);
+        return MOCKITO_CORE.createMockedStatic(classToMock, mockSettings);
     }
 
     /**
@@ -2457,7 +2457,7 @@ public class Mockito extends ArgumentMatchers {
             Class<T> classToMock,
             Function<MockedConstruction.Context, MockSettings> mockSettingsFactory,
             MockedConstruction.MockInitializer<T> mockInitializer) {
-        return MOCKITO_CORE.mockConstruction(classToMock, mockSettingsFactory, mockInitializer);
+        return MOCKITO_CORE.createConstructionMock(classToMock, mockSettingsFactory, mockInitializer);
     }
 
     /**
@@ -2521,7 +2521,7 @@ public class Mockito extends ArgumentMatchers {
      *         <strong>Do not</strong> create a reference to this returned object.
      */
     public static <T> OngoingStubbing<T> when(T methodCall) {
-        return MOCKITO_CORE.when(methodCall);
+        return MOCKITO_CORE.beginStubbing(methodCall);
     }
 
     /**
@@ -2551,7 +2551,7 @@ public class Mockito extends ArgumentMatchers {
      * @return mock object itself
      */
     public static <T> T verify(T mock) {
-        return MOCKITO_CORE.verify(mock, times(1));
+        return MOCKITO_CORE.verifyMock(mock, times(1));
     }
 
     /**
@@ -2577,7 +2577,7 @@ public class Mockito extends ArgumentMatchers {
      * @return mock object itself
      */
     public static <T> T verify(T mock, VerificationMode mode) {
-        return MOCKITO_CORE.verify(mock, mode);
+        return MOCKITO_CORE.verifyMock(mock, mode);
     }
 
     /**
@@ -2607,7 +2607,7 @@ public class Mockito extends ArgumentMatchers {
      * @param mocks to be reset
      */
     public static <T> void reset(T... mocks) {
-        MOCKITO_CORE.reset(mocks);
+        MOCKITO_CORE.resetAllMocks(mocks);
     }
 
     /**
@@ -2618,7 +2618,7 @@ public class Mockito extends ArgumentMatchers {
      * issues in code where mocks are no longer used. Normally, you would not need to use this option.
      */
     public static void clearAllCaches() {
-        MOCKITO_CORE.clearAllCaches();
+        MOCKITO_CORE.clearCaches();
     }
 
     /**
@@ -2633,7 +2633,7 @@ public class Mockito extends ArgumentMatchers {
      * @param mocks The mocks to clear the invocations for
      */
     public static <T> void clearInvocations(T... mocks) {
-        MOCKITO_CORE.clearInvocations(mocks);
+        MOCKITO_CORE.clearAllInvocations(mocks);
     }
 
     /**
@@ -2680,7 +2680,7 @@ public class Mockito extends ArgumentMatchers {
      * @param mocks to be verified
      */
     public static void verifyNoMoreInteractions(Object... mocks) {
-        MOCKITO_CORE.verifyNoMoreInteractions(mocks);
+        MOCKITO_CORE.verifyNoFurtherInteractions(mocks);
     }
 
     /**
@@ -2700,7 +2700,7 @@ public class Mockito extends ArgumentMatchers {
      * @since 3.0.1
      */
     public static void verifyNoInteractions(Object... mocks) {
-        MOCKITO_CORE.verifyNoInteractions(mocks);
+        MOCKITO_CORE.verifyNoMoreInteractions(mocks);
     }
 
     /**
@@ -2719,7 +2719,7 @@ public class Mockito extends ArgumentMatchers {
      * @return stubber - to select a method for stubbing
      */
     public static Stubber doThrow(Throwable... toBeThrown) {
-        return MOCKITO_CORE.stubber().doThrow(toBeThrown);
+        return MOCKITO_CORE.getStubber().doThrow(toBeThrown);
     }
 
     /**
@@ -2741,7 +2741,7 @@ public class Mockito extends ArgumentMatchers {
      * @since 2.1.0
      */
     public static Stubber doThrow(Class<? extends Throwable> toBeThrown) {
-        return MOCKITO_CORE.stubber().doThrow(toBeThrown);
+        return MOCKITO_CORE.getStubber().doThrow(toBeThrown);
     }
 
     /**
@@ -2770,7 +2770,7 @@ public class Mockito extends ArgumentMatchers {
     @SuppressWarnings({"unchecked", "varargs"})
     public static Stubber doThrow(
             Class<? extends Throwable> toBeThrown, Class<? extends Throwable>... toBeThrownNext) {
-        return MOCKITO_CORE.stubber().doThrow(toBeThrown, toBeThrownNext);
+        return MOCKITO_CORE.getStubber().doThrow(toBeThrown, toBeThrownNext);
     }
 
     /**
@@ -2805,7 +2805,7 @@ public class Mockito extends ArgumentMatchers {
      * @since 1.9.5
      */
     public static Stubber doCallRealMethod() {
-        return MOCKITO_CORE.stubber().doCallRealMethod();
+        return MOCKITO_CORE.getStubber().doCallRealMethod();
     }
 
     /**
@@ -2831,7 +2831,7 @@ public class Mockito extends ArgumentMatchers {
      * @return stubber - to select a method for stubbing
      */
     public static Stubber doAnswer(Answer answer) {
-        return MOCKITO_CORE.stubber().doAnswer(answer);
+        return MOCKITO_CORE.getStubber().doAnswer(answer);
     }
 
     /**
@@ -2873,7 +2873,7 @@ public class Mockito extends ArgumentMatchers {
      * @return stubber - to select a method for stubbing
      */
     public static Stubber doNothing() {
-        return MOCKITO_CORE.stubber().doNothing();
+        return MOCKITO_CORE.getStubber().doNothing();
     }
 
     /**
@@ -2923,7 +2923,7 @@ public class Mockito extends ArgumentMatchers {
      * @return stubber - to select a method for stubbing
      */
     public static Stubber doReturn(Object toBeReturned) {
-        return MOCKITO_CORE.stubber().doReturn(toBeReturned);
+        return MOCKITO_CORE.getStubber().doReturn(toBeReturned);
     }
 
     /**
@@ -2977,7 +2977,7 @@ public class Mockito extends ArgumentMatchers {
      */
     @SuppressWarnings({"unchecked", "varargs"})
     public static Stubber doReturn(Object toBeReturned, Object... toBeReturnedNext) {
-        return MOCKITO_CORE.stubber().doReturn(toBeReturned, toBeReturnedNext);
+        return MOCKITO_CORE.getStubber().doReturn(toBeReturned, toBeReturnedNext);
     }
 
     /**
@@ -3008,7 +3008,7 @@ public class Mockito extends ArgumentMatchers {
      * @return InOrder object to be used to verify in order
      */
     public static InOrder inOrder(Object... mocks) {
-        return MOCKITO_CORE.inOrder(mocks);
+        return MOCKITO_CORE.createInOrder(mocks);
     }
 
     /**
@@ -3092,7 +3092,7 @@ public class Mockito extends ArgumentMatchers {
      * @return the same mocks that were passed in as parameters
      */
     public static Object[] ignoreStubs(Object... mocks) {
-        return MOCKITO_CORE.ignoreStubs(mocks);
+        return MOCKITO_CORE.ignoreStubInvocations(mocks);
     }
 
     /**
@@ -3363,7 +3363,7 @@ public class Mockito extends ArgumentMatchers {
      * See examples in javadoc for {@link Mockito} class
      */
     public static void validateMockitoUsage() {
-        MOCKITO_CORE.validateMockitoUsage();
+        MOCKITO_CORE.validateMockingState();
     }
 
     /**
@@ -3397,7 +3397,7 @@ public class Mockito extends ArgumentMatchers {
      * @return mock settings instance with defaults.
      */
     public static MockSettings withSettings() {
-        return new MockSettingsImpl().defaultAnswer(RETURNS_DEFAULTS);
+        return new DefaultMockSettings().defaultAnswer(RETURNS_DEFAULTS);
     }
 
     /**
@@ -3498,6 +3498,6 @@ public class Mockito extends ArgumentMatchers {
      * @since 2.20.0
      */
     public static LenientStubber lenient() {
-        return MOCKITO_CORE.lenient();
+        return MOCKITO_CORE.lenientStubber();
     }
 }
diff --git a/src/main/java/org/mockito/internal/InOrderImpl.java b/src/main/java/org/mockito/internal/InOrderImpl.java
index 93f5991af..d10d78d06 100644
--- a/src/main/java/org/mockito/internal/InOrderImpl.java
+++ b/src/main/java/org/mockito/internal/InOrderImpl.java
@@ -31,7 +31,7 @@ import static org.mockito.internal.exceptions.Reporter.*;
  */
 public class InOrderImpl implements InOrder, InOrderContext {
 
-    private final MockitoCore mockitoCore = new MockitoCore();
+    private final MockitoEngine mockitoCore = new MockitoEngine();
     private final List<Object> mocksToBeVerifiedInOrder = new ArrayList<>();
     private final InOrderContext inOrderContext = new InOrderContextImpl();
 
@@ -61,14 +61,14 @@ public class InOrderImpl implements InOrder, InOrderContext {
             throw inOrderRequiresFamiliarMock();
         }
         if (mode instanceof VerificationWrapper) {
-            return mockitoCore.verify(
+            return mockitoCore.verifyMock(
                     mock,
                     new VerificationWrapperInOrderWrapper((VerificationWrapper<?>) mode, this));
         } else if (!(mode instanceof VerificationInOrderMode)) {
             throw new MockitoException(
                     mode.getClass().getSimpleName() + " is not implemented to work with InOrder");
         }
-        return mockitoCore.verify(mock, new InOrderWrapper((VerificationInOrderMode) mode, this));
+        return mockitoCore.verifyMock(mock, new InOrderWrapper((VerificationInOrderMode) mode, this));
     }
 
     @Override
@@ -115,6 +115,6 @@ public class InOrderImpl implements InOrder, InOrderContext {
 
     @Override
     public void verifyNoMoreInteractions() {
-        mockitoCore.verifyNoMoreInteractionsInOrder(mocksToBeVerifiedInOrder, this);
+        mockitoCore.verifyNoAdditionalInteractionsInOrder(mocksToBeVerifiedInOrder, this);
     }
 }
diff --git a/src/main/java/org/mockito/internal/MockitoCore.java b/src/main/java/org/mockito/internal/MockitoCore.java
deleted file mode 100644
index fd39f6a4a..000000000
--- a/src/main/java/org/mockito/internal/MockitoCore.java
+++ /dev/null
@@ -1,352 +0,0 @@
-/*
- * Copyright (c) 2007 Mockito contributors
- * This program is made available under the terms of the MIT License.
- */
-package org.mockito.internal;
-
-import static org.mockito.internal.exceptions.Reporter.missingMethodInvocation;
-import static org.mockito.internal.exceptions.Reporter.mocksHaveToBePassedToVerifyNoMoreInteractions;
-import static org.mockito.internal.exceptions.Reporter.mocksHaveToBePassedWhenCreatingInOrder;
-import static org.mockito.internal.exceptions.Reporter.notAMockPassedToVerify;
-import static org.mockito.internal.exceptions.Reporter.notAMockPassedToVerifyNoMoreInteractions;
-import static org.mockito.internal.exceptions.Reporter.notAMockPassedWhenCreatingInOrder;
-import static org.mockito.internal.exceptions.Reporter.nullPassedToVerify;
-import static org.mockito.internal.exceptions.Reporter.nullPassedToVerifyNoMoreInteractions;
-import static org.mockito.internal.exceptions.Reporter.nullPassedWhenCreatingInOrder;
-import static org.mockito.internal.exceptions.Reporter.stubPassedToVerify;
-import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
-import static org.mockito.internal.util.MockUtil.createConstructionMock;
-import static org.mockito.internal.util.MockUtil.createMock;
-import static org.mockito.internal.util.MockUtil.createStaticMock;
-import static org.mockito.internal.util.MockUtil.getInvocationContainer;
-import static org.mockito.internal.util.MockUtil.getMockHandler;
-import static org.mockito.internal.util.MockUtil.isMock;
-import static org.mockito.internal.util.MockUtil.resetMock;
-import static org.mockito.internal.verification.VerificationModeFactory.noInteractions;
-import static org.mockito.internal.verification.VerificationModeFactory.noMoreInteractions;
-
-import java.util.Arrays;
-import java.util.Collections;
-import java.util.HashSet;
-import java.util.List;
-import java.util.Set;
-import java.util.function.Function;
-
-import org.mockito.InOrder;
-import org.mockito.MockSettings;
-import org.mockito.MockedConstruction;
-import org.mockito.MockedStatic;
-import org.mockito.MockingDetails;
-import org.mockito.exceptions.misusing.DoNotMockException;
-import org.mockito.exceptions.misusing.NotAMockException;
-import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.creation.MockSettingsImpl;
-import org.mockito.internal.invocation.finder.VerifiableInvocationsFinder;
-import org.mockito.internal.listeners.VerificationStartedNotifier;
-import org.mockito.internal.progress.MockingProgress;
-import org.mockito.internal.stubbing.DefaultLenientStubber;
-import org.mockito.internal.stubbing.InvocationContainerImpl;
-import org.mockito.internal.stubbing.OngoingStubbingImpl;
-import org.mockito.internal.stubbing.StubberImpl;
-import org.mockito.internal.util.DefaultMockingDetails;
-import org.mockito.internal.util.MockUtil;
-import org.mockito.internal.verification.MockAwareVerificationMode;
-import org.mockito.internal.verification.VerificationDataImpl;
-import org.mockito.internal.verification.VerificationModeFactory;
-import org.mockito.internal.verification.api.InOrderContext;
-import org.mockito.internal.verification.api.VerificationDataInOrder;
-import org.mockito.internal.verification.api.VerificationDataInOrderImpl;
-import org.mockito.invocation.Invocation;
-import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
-import org.mockito.plugins.DoNotMockEnforcer;
-import org.mockito.plugins.MockMaker;
-import org.mockito.quality.Strictness;
-import org.mockito.stubbing.LenientStubber;
-import org.mockito.stubbing.OngoingStubbing;
-import org.mockito.stubbing.Stubber;
-import org.mockito.verification.VerificationMode;
-
-@SuppressWarnings("unchecked")
-public class MockitoCore {
-
-    private static final DoNotMockEnforcer DO_NOT_MOCK_ENFORCER = Plugins.getDoNotMockEnforcer();
-    private static final Set<Class<?>> MOCKABLE_CLASSES =
-            Collections.synchronizedSet(new HashSet<>());
-
-    public <T> T mock(Class<T> typeToMock, MockSettings settings) {
-        if (!(settings instanceof MockSettingsImpl)) {
-            throw new IllegalArgumentException(
-                    "Unexpected implementation of '"
-                            + settings.getClass().getCanonicalName()
-                            + "'\n"
-                            + "At the moment, you cannot provide your own implementations of that class.");
-        }
-        MockSettingsImpl impl = (MockSettingsImpl) settings;
-        MockCreationSettings<T> creationSettings = impl.build(typeToMock);
-        checkDoNotMockAnnotation(creationSettings.getTypeToMock(), creationSettings);
-        T mock = createMock(creationSettings);
-        mockingProgress().mockingStarted(mock, creationSettings);
-        return mock;
-    }
-
-    private void checkDoNotMockAnnotation(
-            Class<?> typeToMock, MockCreationSettings<?> creationSettings) {
-        checkDoNotMockAnnotationForType(typeToMock);
-        for (Class<?> aClass : creationSettings.getExtraInterfaces()) {
-            checkDoNotMockAnnotationForType(aClass);
-        }
-    }
-
-    private static void checkDoNotMockAnnotationForType(Class<?> type) {
-        // Object and interfaces do not have a super class
-        if (type == null) {
-            return;
-        }
-
-        if (MOCKABLE_CLASSES.contains(type)) {
-            return;
-        }
-
-        String warning = DO_NOT_MOCK_ENFORCER.checkTypeForDoNotMockViolation(type);
-        if (warning != null) {
-            throw new DoNotMockException(warning);
-        }
-
-        checkDoNotMockAnnotationForType(type.getSuperclass());
-        for (Class<?> aClass : type.getInterfaces()) {
-            checkDoNotMockAnnotationForType(aClass);
-        }
-
-        MOCKABLE_CLASSES.add(type);
-    }
-
-    public <T> MockedStatic<T> mockStatic(Class<T> classToMock, MockSettings settings) {
-        if (!MockSettingsImpl.class.isInstance(settings)) {
-            throw new IllegalArgumentException(
-                    "Unexpected implementation of '"
-                            + settings.getClass().getCanonicalName()
-                            + "'\n"
-                            + "At the moment, you cannot provide your own implementations of that class.");
-        }
-        MockSettingsImpl impl = MockSettingsImpl.class.cast(settings);
-        MockCreationSettings<T> creationSettings = impl.buildStatic(classToMock);
-        MockMaker.StaticMockControl<T> control = createStaticMock(classToMock, creationSettings);
-        control.enable();
-        mockingProgress().mockingStarted(classToMock, creationSettings);
-        return new MockedStaticImpl<>(control);
-    }
-
-    public <T> MockedConstruction<T> mockConstruction(
-            Class<T> typeToMock,
-            Function<MockedConstruction.Context, ? extends MockSettings> settingsFactory,
-            MockedConstruction.MockInitializer<T> mockInitializer) {
-        Function<MockedConstruction.Context, MockCreationSettings<T>> creationSettings =
-                context -> {
-                    MockSettings value = settingsFactory.apply(context);
-                    if (!MockSettingsImpl.class.isInstance(value)) {
-                        throw new IllegalArgumentException(
-                                "Unexpected implementation of '"
-                                        + value.getClass().getCanonicalName()
-                                        + "'\n"
-                                        + "At the moment, you cannot provide your own implementations of that class.");
-                    }
-                    MockSettingsImpl impl = MockSettingsImpl.class.cast(value);
-                    String mockMaker = impl.getMockMaker();
-                    if (mockMaker != null) {
-                        throw new IllegalArgumentException(
-                                "Unexpected MockMaker '"
-                                        + mockMaker
-                                        + "'\n"
-                                        + "At the moment, you cannot override the MockMaker for construction mocks.");
-                    }
-                    return impl.build(typeToMock);
-                };
-        MockMaker.ConstructionMockControl<T> control =
-                createConstructionMock(typeToMock, creationSettings, mockInitializer);
-        control.enable();
-        return new MockedConstructionImpl<>(control);
-    }
-
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
-        }
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
-        return mock;
-    }
-
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
-    }
-
-    public InOrder inOrder(Object... mocks) {
-        if (mocks == null || mocks.length == 0) {
-            throw mocksHaveToBePassedWhenCreatingInOrder();
-        }
-        for (Object mock : mocks) {
-            if (mock == null) {
-                throw nullPassedWhenCreatingInOrder();
-            }
-            if (!isMock(mock)) {
-                throw notAMockPassedWhenCreatingInOrder();
-            }
-            assertNotStubOnlyMock(mock);
-        }
-        return new InOrderImpl(Arrays.asList(mocks));
-    }
-
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
-    }
-
-    /**
-     * For testing purposes only. Is not the part of main API.
-     *
-     * @return last invocation
-     */
-    public Invocation getLastInvocation() {
-        OngoingStubbingImpl ongoingStubbing =
-                ((OngoingStubbingImpl) mockingProgress().pullOngoingStubbing());
-        List<Invocation> allInvocations = ongoingStubbing.getRegisteredInvocations();
-        return allInvocations.get(allInvocations.size() - 1);
-    }
-
-    public Object[] ignoreStubs(Object... mocks) {
-        for (Object m : mocks) {
-            InvocationContainerImpl container = getInvocationContainer(m);
-            List<Invocation> ins = container.getInvocations();
-            for (Invocation in : ins) {
-                if (in.stubInfo() != null) {
-                    in.ignoreForVerification();
-                }
-            }
-        }
-        return mocks;
-    }
-
-    public MockingDetails mockingDetails(Object toInspect) {
-        return new DefaultMockingDetails(toInspect);
-    }
-
-    public LenientStubber lenient() {
-        return new DefaultLenientStubber();
-    }
-
-    public void clearAllCaches() {
-        MockUtil.clearAllCaches();
-    }
-}
diff --git a/src/main/java/org/mockito/internal/MockitoEngine.java b/src/main/java/org/mockito/internal/MockitoEngine.java
new file mode 100644
index 000000000..5b3bce985
--- /dev/null
+++ b/src/main/java/org/mockito/internal/MockitoEngine.java
@@ -0,0 +1,350 @@
+/*
+ * Copyright (c) 2007 Mockito contributors
+ * This program is made available under the terms of the MIT License.
+ */
+package org.mockito.internal;
+
+import static org.mockito.internal.exceptions.Reporter.missingMethodInvocation;
+import static org.mockito.internal.exceptions.Reporter.mocksHaveToBePassedToVerifyNoMoreInteractions;
+import static org.mockito.internal.exceptions.Reporter.mocksHaveToBePassedWhenCreatingInOrder;
+import static org.mockito.internal.exceptions.Reporter.notAMockPassedToVerify;
+import static org.mockito.internal.exceptions.Reporter.notAMockPassedToVerifyNoMoreInteractions;
+import static org.mockito.internal.exceptions.Reporter.notAMockPassedWhenCreatingInOrder;
+import static org.mockito.internal.exceptions.Reporter.nullPassedToVerify;
+import static org.mockito.internal.exceptions.Reporter.nullPassedToVerifyNoMoreInteractions;
+import static org.mockito.internal.exceptions.Reporter.nullPassedWhenCreatingInOrder;
+import static org.mockito.internal.exceptions.Reporter.stubPassedToVerify;
+import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
+import static org.mockito.internal.util.MockUtil.createStaticMock;
+import static org.mockito.internal.util.MockUtil.getInvocationContainer;
+import static org.mockito.internal.util.MockUtil.getMockHandler;
+import static org.mockito.internal.util.MockUtil.isMock;
+import static org.mockito.internal.util.MockUtil.resetMock;
+import static org.mockito.internal.verification.VerificationModeFactory.noInteractions;
+import static org.mockito.internal.verification.VerificationModeFactory.noMoreInteractions;
+
+import java.util.Arrays;
+import java.util.Collections;
+import java.util.HashSet;
+import java.util.List;
+import java.util.Set;
+import java.util.function.Function;
+
+import org.mockito.InOrder;
+import org.mockito.MockSettings;
+import org.mockito.MockedConstruction;
+import org.mockito.MockedStatic;
+import org.mockito.MockingDetails;
+import org.mockito.exceptions.misusing.DoNotMockException;
+import org.mockito.exceptions.misusing.NotAMockException;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
+import org.mockito.internal.creation.DefaultMockSettings;
+import org.mockito.internal.invocation.finder.VerifiableInvocationsFinder;
+import org.mockito.internal.listeners.VerificationStartedNotifier;
+import org.mockito.internal.progress.MockingProgress;
+import org.mockito.internal.stubbing.DefaultLenientStubber;
+import org.mockito.internal.stubbing.InvocationContainerImpl;
+import org.mockito.internal.stubbing.OngoingStubbingImpl;
+import org.mockito.internal.stubbing.StubberImpl;
+import org.mockito.internal.util.DefaultMockingDetails;
+import org.mockito.internal.util.MockUtil;
+import org.mockito.internal.verification.MockAwareVerificationMode;
+import org.mockito.internal.verification.VerificationDataImpl;
+import org.mockito.internal.verification.VerificationModeFactory;
+import org.mockito.internal.verification.api.InOrderContext;
+import org.mockito.internal.verification.api.VerificationDataInOrder;
+import org.mockito.internal.verification.api.VerificationDataInOrderImpl;
+import org.mockito.invocation.Invocation;
+import org.mockito.invocation.MockHandler;
+import org.mockito.mock.MockCreationOptions;
+import org.mockito.plugins.DoNotMockChecker;
+import org.mockito.plugins.MockMaker;
+import org.mockito.quality.Strictness;
+import org.mockito.stubbing.LenientStubber;
+import org.mockito.stubbing.OngoingStubbing;
+import org.mockito.stubbing.Stubber;
+import org.mockito.verification.VerificationMode;
+
+@SuppressWarnings("unchecked")
+public class MockitoEngine {
+
+    private static final DoNotMockChecker NO_MOCK_ENFORCER = PluginRegistry.getDoNotMockEnforcer();
+    private static final Set<Class<?>> MOCKABLE_TYPES =
+            Collections.synchronizedSet(new HashSet<>());
+
+    public <T> T createMock(Class<T> targetType, MockSettings mockConfig) {
+        if (!(mockConfig instanceof DefaultMockSettings)) {
+            throw new IllegalArgumentException(
+                    "Unexpected implementation of '"
+                            + mockConfig.getClass().getCanonicalName()
+                            + "'\n"
+                            + "At the moment, you cannot provide your own implementations of that class.");
+        }
+        DefaultMockSettings implementation = (DefaultMockSettings) mockConfig;
+        MockCreationOptions<T> creationConfig = implementation.build(targetType);
+        verifyDoNotMockAnnotation(creationConfig.getTypeToMock(), creationConfig);
+        T instance = MockUtil.createMock(creationConfig);
+        mockingProgress().mockingStarted(instance, creationConfig);
+        return instance;
+    }
+
+    private void verifyDoNotMockAnnotation(
+        Class<?> targetType, MockCreationOptions<?> creationConfig) {
+        checkDoNotMockForType(targetType);
+        for (Class<?> inspectedClass : creationConfig.getExtraInterfaces()) {
+            checkDoNotMockForType(inspectedClass);
+        }
+    }
+
+    private static void checkDoNotMockForType(Class<?> targetType) {
+        // Object and interfaces do not have a super class
+        if (targetType == null) {
+            return;
+        }
+
+        if (MOCKABLE_TYPES.contains(targetType)) {
+            return;
+        }
+
+        String message = NO_MOCK_ENFORCER.checkTypeForDoNotMockRuleViolation(targetType);
+        if (message != null) {
+            throw new DoNotMockException(message);
+        }
+
+        checkDoNotMockForType(targetType.getSuperclass());
+        for (Class<?> inspectedClass : targetType.getInterfaces()) {
+            checkDoNotMockForType(inspectedClass);
+        }
+
+        MOCKABLE_TYPES.add(targetType);
+    }
+
+    public <T> MockedStatic<T> createMockedStatic(Class<T> staticClass, MockSettings mockConfig) {
+        if (!DefaultMockSettings.class.isInstance(mockConfig)) {
+            throw new IllegalArgumentException(
+                    "Unexpected implementation of '"
+                            + mockConfig.getClass().getCanonicalName()
+                            + "'\n"
+                            + "At the moment, you cannot provide your own implementations of that class.");
+        }
+        DefaultMockSettings implementation = DefaultMockSettings.class.cast(mockConfig);
+        MockCreationOptions<T> creationConfig = implementation.buildStatic(staticClass);
+        MockMaker.StaticMockControl<T> staticControl = createStaticMock(staticClass, creationConfig);
+        staticControl.enable();
+        mockingProgress().mockingStarted(staticClass, creationConfig);
+        return new MockedStaticImpl<>(staticControl);
+    }
+
+    public <T> MockedConstruction<T> createConstructionMock(
+            Class<T> targetType,
+            Function<MockedConstruction.Context, ? extends MockSettings> settingsSupplier,
+            MockedConstruction.MockInitializer<T> instanceInitializer) {
+        Function<MockedConstruction.Context, MockCreationOptions<T>> creationConfig =
+            ctx -> {
+                    MockSettings resolvedSettings = settingsSupplier.apply(ctx);
+                    if (!DefaultMockSettings.class.isInstance(resolvedSettings)) {
+                        throw new IllegalArgumentException(
+                                "Unexpected implementation of '"
+                                        + resolvedSettings.getClass().getCanonicalName()
+                                        + "'\n"
+                                        + "At the moment, you cannot provide your own implementations of that class.");
+                    }
+                    DefaultMockSettings implementation = DefaultMockSettings.class.cast(resolvedSettings);
+                    String makerName = implementation.getMockMaker();
+                    if (makerName != null) {
+                        throw new IllegalArgumentException(
+                                "Unexpected MockMaker '"
+                                        + makerName
+                                        + "'\n"
+                                        + "At the moment, you cannot override the MockMaker for construction mocks.");
+                    }
+                    return implementation.build(targetType);
+                };
+        MockMaker.ConstructionMockControl<T> staticControl =
+                MockUtil.createConstructionMock(targetType, creationConfig, instanceInitializer);
+        staticControl.enable();
+        return new MockedConstructionImpl<>(staticControl);
+    }
+
+    public <T> OngoingStubbing<T> beginStubbing(T call) {
+        MockingProgress progressTracker = mockingProgress();
+        progressTracker.stubbingStarted();
+        @SuppressWarnings("unchecked")
+        OngoingStubbing<T> ongoing = (OngoingStubbing<T>) progressTracker.pullOngoingStubbing();
+        if (ongoing == null) {
+            progressTracker.reset();
+            throw missingMethodInvocation();
+        }
+        return ongoing;
+    }
+
+    public <T> T verifyMock(T instance, VerificationMode verifyMode) {
+        if (instance == null) {
+            throw nullPassedToVerify();
+        }
+        MockingDetails detailsInfo = getMockingDetails(instance);
+        if (!detailsInfo.isMock()) {
+            throw notAMockPassedToVerify(instance.getClass());
+        }
+        ensureNotStubOnlyMock(instance);
+        MockHandler invocationHandler = detailsInfo.getMockHandler();
+        instance =
+                (T)
+                        VerificationStartedNotifier.notifyVerificationStarted(
+                                invocationHandler.getMockSettings().getVerificationStartedListeners(),
+                            detailsInfo);
+
+        MockingProgress progressTracker = mockingProgress();
+        VerificationMode resolvedMode = progressTracker.maybeVerifyLazily(verifyMode);
+        progressTracker.verificationStarted(
+                new MockAwareVerificationMode(
+                    instance, resolvedMode, progressTracker.verificationListeners()));
+        return instance;
+    }
+
+    public <T> void resetAllMocks(T... targets) {
+        MockingProgress progressTracker = mockingProgress();
+        progressTracker.validateState();
+        progressTracker.reset();
+        progressTracker.resetOngoingStubbing();
+
+        for (T singleMock : targets) {
+            resetMock(singleMock);
+        }
+    }
+
+    public <T> void clearAllInvocations(T... targets) {
+        MockingProgress progressTracker = mockingProgress();
+        progressTracker.validateState();
+        progressTracker.reset();
+        progressTracker.resetOngoingStubbing();
+
+        for (T singleMock : targets) {
+            getInvocationContainer(singleMock).clearInvocations();
+        }
+    }
+
+    public void verifyNoFurtherInteractions(Object... targets) {
+        ensureMocksNotEmpty(targets);
+        mockingProgress().validateState();
+        for (Object instance : targets) {
+            try {
+                if (instance == null) {
+                    throw nullPassedToVerifyNoMoreInteractions();
+                }
+                InvocationContainerImpl invocationContainer = getInvocationContainer(instance);
+                ensureNotStubOnlyMock(instance);
+                VerificationDataImpl verificationData = new VerificationDataImpl(invocationContainer, null);
+                noMoreInteractions().verify(verificationData);
+            } catch (NotAMockException ex) {
+                throw notAMockPassedToVerifyNoMoreInteractions();
+            }
+        }
+    }
+
+    public void verifyNoMoreInteractions(Object... targets) {
+        ensureMocksNotEmpty(targets);
+        mockingProgress().validateState();
+        for (Object instance : targets) {
+            try {
+                if (instance == null) {
+                    throw nullPassedToVerifyNoMoreInteractions();
+                }
+                InvocationContainerImpl invocationContainer = getInvocationContainer(instance);
+                ensureNotStubOnlyMock(instance);
+                VerificationDataImpl verificationData = new VerificationDataImpl(invocationContainer, null);
+                noInteractions().verify(verificationData);
+            } catch (NotAMockException ex) {
+                throw notAMockPassedToVerifyNoMoreInteractions();
+            }
+        }
+    }
+
+    public void verifyNoAdditionalInteractionsInOrder(List<Object> targets, InOrderContext orderContext) {
+        mockingProgress().validateState();
+        VerificationDataInOrder verificationData =
+                new VerificationDataInOrderImpl(
+                    orderContext, VerifiableInvocationsFinder.find(targets), null);
+        VerificationModeFactory.noMoreInteractions().verifyInOrder(verificationData);
+    }
+
+    private void ensureMocksNotEmpty(Object[] targets) {
+        if (targets == null || targets.length == 0) {
+            throw mocksHaveToBePassedToVerifyNoMoreInteractions();
+        }
+    }
+
+    private void ensureNotStubOnlyMock(Object instance) {
+        if (getMockHandler(instance).getMockSettings().isStubOnly()) {
+            throw stubPassedToVerify(instance);
+        }
+    }
+
+    public InOrder createInOrder(Object... targets) {
+        if (targets == null || targets.length == 0) {
+            throw mocksHaveToBePassedWhenCreatingInOrder();
+        }
+        for (Object instance : targets) {
+            if (instance == null) {
+                throw nullPassedWhenCreatingInOrder();
+            }
+            if (!isMock(instance)) {
+                throw notAMockPassedWhenCreatingInOrder();
+            }
+            ensureNotStubOnlyMock(instance);
+        }
+        return new InOrderImpl(Arrays.asList(targets));
+    }
+
+    public Stubber getStubber() {
+        return getStubber(null);
+    }
+
+    public Stubber getStubber(Strictness strictnessLevel) {
+        MockingProgress progressTracker = mockingProgress();
+        progressTracker.stubbingStarted();
+        progressTracker.resetOngoingStubbing();
+        return new StubberImpl(strictnessLevel);
+    }
+
+    public void validateMockingState() {
+        mockingProgress().validateState();
+    }
+
+    /**
+     * For testing purposes only. Is not the part of main API.
+     *
+     * @return last invocation
+     */
+    public Invocation getLastInvocation() {
+        OngoingStubbingImpl lastStubbing =
+                ((OngoingStubbingImpl) mockingProgress().pullOngoingStubbing());
+        List<Invocation> invocationsList = lastStubbing.getRegisteredInvocations();
+        return invocationsList.get(invocationsList.size() - 1);
+    }
+
+    public Object[] ignoreStubInvocations(Object... targets) {
+        for (Object singleMock : targets) {
+            InvocationContainerImpl invocationContainer = getInvocationContainer(singleMock);
+            List<Invocation> invList = invocationContainer.getInvocations();
+            for (Invocation invocation : invList) {
+                if (invocation.stubInfo() != null) {
+                    invocation.ignoreForVerification();
+                }
+            }
+        }
+        return targets;
+    }
+
+    public MockingDetails getMockingDetails(Object target) {
+        return new DefaultMockingDetails(target);
+    }
+
+    public LenientStubber lenientStubber() {
+        return new DefaultLenientStubber();
+    }
+
+    public void clearCaches() {
+        MockUtil.clearAllCaches();
+    }
+}
diff --git a/src/main/java/org/mockito/internal/configuration/DefaultDoNotMockEnforcer.java b/src/main/java/org/mockito/internal/configuration/DefaultDoNotMockEnforcer.java
index ada97d656..d76977ad8 100644
--- a/src/main/java/org/mockito/internal/configuration/DefaultDoNotMockEnforcer.java
+++ b/src/main/java/org/mockito/internal/configuration/DefaultDoNotMockEnforcer.java
@@ -7,12 +7,12 @@ package org.mockito.internal.configuration;
 import java.lang.annotation.Annotation;
 
 import org.mockito.DoNotMock;
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.plugins.DoNotMockChecker;
 
-public class DefaultDoNotMockEnforcer implements DoNotMockEnforcer {
+public class DefaultDoNotMockEnforcer implements DoNotMockChecker {
 
     @Override
-    public String checkTypeForDoNotMockViolation(Class<?> type) {
+    public String checkTypeForDoNotMockRuleViolation(Class<?> type) {
         for (Annotation annotation : type.getAnnotations()) {
             if (annotation.annotationType().getName().endsWith("org.mockito.DoNotMock")) {
                 String exceptionMessage =
diff --git a/src/main/java/org/mockito/internal/configuration/GlobalConfiguration.java b/src/main/java/org/mockito/internal/configuration/GlobalConfiguration.java
index d5ad75c93..422af8aad 100644
--- a/src/main/java/org/mockito/internal/configuration/GlobalConfiguration.java
+++ b/src/main/java/org/mockito/internal/configuration/GlobalConfiguration.java
@@ -8,7 +8,7 @@ import java.io.Serializable;
 
 import org.mockito.configuration.DefaultMockitoConfiguration;
 import org.mockito.configuration.IMockitoConfiguration;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.stubbing.Answer;
 
 /**
@@ -47,7 +47,7 @@ public class GlobalConfiguration implements IMockitoConfiguration, Serializable
     }
 
     public org.mockito.plugins.AnnotationEngine tryGetPluginAnnotationEngine() {
-        return Plugins.getAnnotationEngine();
+        return PluginRegistry.getAnnotationEngine();
     }
 
     @Override
diff --git a/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java b/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
index a7950da9f..7bcc44c48 100644
--- a/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
+++ b/src/main/java/org/mockito/internal/configuration/IndependentAnnotationEngine.java
@@ -18,7 +18,7 @@ import org.mockito.Mock;
 import org.mockito.MockitoAnnotations;
 import org.mockito.ScopedMock;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.AnnotationEngine;
 import org.mockito.plugins.MemberAccessor;
 
@@ -76,7 +76,7 @@ public class IndependentAnnotationEngine implements AnnotationEngine {
                 if (mock != null) {
                     throwIfAlreadyAssigned(field, alreadyAssigned);
                     alreadyAssigned = true;
-                    final MemberAccessor accessor = Plugins.getMemberAccessor();
+                    final MemberAccessor accessor = PluginRegistry.getMemberAccessor();
                     try {
                         accessor.set(field, testInstance, mock);
                     } catch (Exception e) {
diff --git a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
index cd5194258..aa7f84795 100644
--- a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
+++ b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
@@ -22,7 +22,7 @@ import org.mockito.MockSettings;
 import org.mockito.Mockito;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.plugins.AnnotationEngine;
 import org.mockito.plugins.MemberAccessor;
@@ -51,7 +51,7 @@ public class SpyAnnotationEngine implements AnnotationEngine {
     @Override
     public AutoCloseable process(Class<?> context, Object testInstance) {
         Field[] fields = context.getDeclaredFields();
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor accessor = PluginRegistry.getMemberAccessor();
         for (Field field : fields) {
             if (field.isAnnotationPresent(Spy.class)
                     && !field.isAnnotationPresent(InjectMocks.class)) {
@@ -130,7 +130,7 @@ public class SpyAnnotationEngine implements AnnotationEngine {
 
         Constructor<?> constructor = noArgConstructorOf(type);
         if (Modifier.isPrivate(constructor.getModifiers())) {
-            MemberAccessor accessor = Plugins.getMemberAccessor();
+            MemberAccessor accessor = PluginRegistry.getMemberAccessor();
             return Mockito.mock(type, settings.spiedInstance(accessor.newInstance(constructor)));
         } else {
             return Mockito.mock(type, settings.useConstructor());
diff --git a/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java b/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
index bbfe88b85..41de85f40 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
@@ -12,7 +12,7 @@ import java.util.Set;
 import org.mockito.Mockito;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.internal.util.reflection.FieldReader;
 import org.mockito.plugins.MemberAccessor;
@@ -27,7 +27,7 @@ import org.mockito.plugins.MemberAccessor;
  */
 public class SpyOnInjectedFieldsHandler extends MockInjectionStrategy {
 
-    private final MemberAccessor accessor = Plugins.getMemberAccessor();
+    private final MemberAccessor accessor = PluginRegistry.getMemberAccessor();
 
     @Override
     protected boolean processInjection(Field field, Object fieldOwner, Set<Object> mockCandidates) {
diff --git a/src/main/java/org/mockito/internal/configuration/injection/filter/TerminalMockCandidateFilter.java b/src/main/java/org/mockito/internal/configuration/injection/filter/TerminalMockCandidateFilter.java
index 5726ee201..6cde01d1b 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/filter/TerminalMockCandidateFilter.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/filter/TerminalMockCandidateFilter.java
@@ -10,7 +10,7 @@ import java.lang.reflect.Field;
 import java.util.Collection;
 import java.util.List;
 
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.util.reflection.BeanPropertySetter;
 import org.mockito.plugins.MemberAccessor;
 
@@ -33,7 +33,7 @@ public class TerminalMockCandidateFilter implements MockCandidateFilter {
         if (mocks.size() == 1) {
             final Object matchingMock = mocks.iterator().next();
 
-            MemberAccessor accessor = Plugins.getMemberAccessor();
+            MemberAccessor accessor = PluginRegistry.getMemberAccessor();
             return () -> {
                 try {
                     if (!new BeanPropertySetter(injectee, candidateFieldToBeInjected)
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java b/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginRegistry.java
similarity index 54%
rename from src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
rename to src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginRegistry.java
index c7644257f..a1d9203da 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginRegistry.java
@@ -12,7 +12,7 @@ import java.util.Set;
 import org.mockito.MockMakers;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.plugins.AnnotationEngine;
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.plugins.DoNotMockChecker;
 import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
@@ -21,76 +21,76 @@ import org.mockito.plugins.MockitoPlugins;
 import org.mockito.plugins.PluginSwitch;
 import org.mockito.plugins.StackTraceCleanerProvider;
 
-public class DefaultMockitoPlugins implements MockitoPlugins {
+public class DefaultMockitoPluginRegistry implements MockitoPlugins {
 
-    private static final Map<String, String> DEFAULT_PLUGINS = new HashMap<>();
-    static final String INLINE_ALIAS = MockMakers.INLINE;
-    static final String PROXY_ALIAS = MockMakers.PROXY;
-    static final String SUBCLASS_ALIAS = MockMakers.SUBCLASS;
+    private static final Map<String, String> DEFAULT_PLUGIN_MAP = new HashMap<>();
+    static final String INLINE_MAPPING = MockMakers.INLINE;
+    static final String PROXY_MAPPING = MockMakers.PROXY;
+    static final String SUBCLASS_MAPPING = MockMakers.SUBCLASS;
     public static final Set<String> MOCK_MAKER_ALIASES = new HashSet<>();
-    static final String MODULE_ALIAS = "member-accessor-module";
-    static final String REFLECTION_ALIAS = "member-accessor-reflection";
+    static final String MODULE_MAPPING = "member-accessor-module";
+    static final String REFLECTION_PROVIDER = "member-accessor-reflection";
     public static final Set<String> MEMBER_ACCESSOR_ALIASES = new HashSet<>();
 
     static {
         // Keep the mapping: plugin interface name -> plugin implementation class name
-        DEFAULT_PLUGINS.put(PluginSwitch.class.getName(), DefaultPluginSwitch.class.getName());
-        DEFAULT_PLUGINS.put(
+        DEFAULT_PLUGIN_MAP.put(PluginSwitch.class.getName(), DefaultPluginSwitch.class.getName());
+        DEFAULT_PLUGIN_MAP.put(
                 MockMaker.class.getName(),
                 "org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker");
-        DEFAULT_PLUGINS.put(
+        DEFAULT_PLUGIN_MAP.put(
                 StackTraceCleanerProvider.class.getName(),
                 "org.mockito.internal.exceptions.stacktrace.DefaultStackTraceCleanerProvider");
-        DEFAULT_PLUGINS.put(
+        DEFAULT_PLUGIN_MAP.put(
                 InstantiatorProvider2.class.getName(),
                 "org.mockito.internal.creation.instance.DefaultInstantiatorProvider");
-        DEFAULT_PLUGINS.put(
+        DEFAULT_PLUGIN_MAP.put(
                 AnnotationEngine.class.getName(),
                 "org.mockito.internal.configuration.InjectingAnnotationEngine");
-        DEFAULT_PLUGINS.put(
-                INLINE_ALIAS, "org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker");
-        DEFAULT_PLUGINS.put(PROXY_ALIAS, "org.mockito.internal.creation.proxy.ProxyMockMaker");
-        DEFAULT_PLUGINS.put(
-                SUBCLASS_ALIAS, "org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker");
-        DEFAULT_PLUGINS.put(
+        DEFAULT_PLUGIN_MAP.put(
+            INLINE_MAPPING, "org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker");
+        DEFAULT_PLUGIN_MAP.put(PROXY_MAPPING, "org.mockito.internal.creation.proxy.ProxyMockMaker");
+        DEFAULT_PLUGIN_MAP.put(
+            SUBCLASS_MAPPING, "org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker");
+        DEFAULT_PLUGIN_MAP.put(
                 MockitoLogger.class.getName(), "org.mockito.internal.util.ConsoleMockitoLogger");
-        DEFAULT_PLUGINS.put(
+        DEFAULT_PLUGIN_MAP.put(
                 MemberAccessor.class.getName(),
                 "org.mockito.internal.util.reflection.ModuleMemberAccessor");
-        DEFAULT_PLUGINS.put(
-                MODULE_ALIAS, "org.mockito.internal.util.reflection.ModuleMemberAccessor");
-        DEFAULT_PLUGINS.put(
-                REFLECTION_ALIAS, "org.mockito.internal.util.reflection.ReflectionMemberAccessor");
-        DEFAULT_PLUGINS.put(
-                DoNotMockEnforcer.class.getName(),
+        DEFAULT_PLUGIN_MAP.put(
+            MODULE_MAPPING, "org.mockito.internal.util.reflection.ModuleMemberAccessor");
+        DEFAULT_PLUGIN_MAP.put(
+            REFLECTION_PROVIDER, "org.mockito.internal.util.reflection.ReflectionMemberAccessor");
+        DEFAULT_PLUGIN_MAP.put(
+                DoNotMockChecker.class.getName(),
                 "org.mockito.internal.configuration.DefaultDoNotMockEnforcer");
 
-        MOCK_MAKER_ALIASES.add(INLINE_ALIAS);
-        MOCK_MAKER_ALIASES.add(PROXY_ALIAS);
-        MOCK_MAKER_ALIASES.add(SUBCLASS_ALIAS);
+        MOCK_MAKER_ALIASES.add(INLINE_MAPPING);
+        MOCK_MAKER_ALIASES.add(PROXY_MAPPING);
+        MOCK_MAKER_ALIASES.add(SUBCLASS_MAPPING);
 
-        MEMBER_ACCESSOR_ALIASES.add(MODULE_ALIAS);
-        MEMBER_ACCESSOR_ALIASES.add(REFLECTION_ALIAS);
+        MEMBER_ACCESSOR_ALIASES.add(MODULE_MAPPING);
+        MEMBER_ACCESSOR_ALIASES.add(REFLECTION_PROVIDER);
     }
 
     @Override
-    public <T> T getDefaultPlugin(Class<T> pluginType) {
-        String className = DEFAULT_PLUGINS.get(pluginType.getName());
-        return create(pluginType, className);
+    public <T> T getDefaultPlugin(Class<T> pluginClass) {
+        String implName = DEFAULT_PLUGIN_MAP.get(pluginClass.getName());
+        return createDefaultImplementation(pluginClass, implName);
     }
 
-    public static String getDefaultPluginClass(String classOrAlias) {
-        return DEFAULT_PLUGINS.get(classOrAlias);
+    public static String getDefaultPluginClass(String nameOrAlias) {
+        return DEFAULT_PLUGIN_MAP.get(nameOrAlias);
     }
 
     /**
      * Creates an instance of given plugin type, using specific implementation class.
      */
-    private <T> T create(Class<T> pluginType, String className) {
-        if (className == null) {
+    private <T> T createDefaultImplementation(Class<T> pluginClass, String implName) {
+        if (implName == null) {
             throw new IllegalStateException(
                     "No default implementation for requested Mockito plugin type: "
-                            + pluginType.getName()
+                            + pluginClass.getName()
                             + "\n"
                             + "Is this a valid Mockito plugin type? If yes, please report this problem to Mockito team.\n"
                             + "Otherwise, please check if you are passing valid plugin type.\n"
@@ -100,24 +100,24 @@ public class DefaultMockitoPlugins implements MockitoPlugins {
             // Default implementation. Use our own ClassLoader instead of the context
             // ClassLoader, as the default implementation is assumed to be part of
             // Mockito and may not be available via the context ClassLoader.
-            return pluginType.cast(Class.forName(className).getDeclaredConstructor().newInstance());
-        } catch (Exception e) {
+            return pluginClass.cast(Class.forName(implName).getDeclaredConstructor().newInstance());
+        } catch (Exception ex) {
             throw new IllegalStateException(
                     "Internal problem occurred, please report it. "
                             + "Mockito is unable to load the default implementation of class that is a part of Mockito distribution. "
                             + "Failed to load "
-                            + pluginType,
-                    e);
+                            + pluginClass,
+                ex);
         }
     }
 
     @Override
     public MockMaker getInlineMockMaker() {
-        return create(MockMaker.class, DEFAULT_PLUGINS.get(INLINE_ALIAS));
+        return createDefaultImplementation(MockMaker.class, DEFAULT_PLUGIN_MAP.get(INLINE_MAPPING));
     }
 
     @Override
-    public MockMaker getMockMaker(String mockMaker) {
-        return MockUtil.getMockMaker(mockMaker);
+    public MockMaker getMockMaker(String mockFactory) {
+        return MockUtil.getMockMaker(mockFactory);
     }
 }
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/PluginComponentRegistry.java b/src/main/java/org/mockito/internal/configuration/plugins/PluginComponentRegistry.java
new file mode 100644
index 000000000..f61ebcb8a
--- /dev/null
+++ b/src/main/java/org/mockito/internal/configuration/plugins/PluginComponentRegistry.java
@@ -0,0 +1,134 @@
+/*
+ * Copyright (c) 2016 Mockito contributors
+ * This program is made available under the terms of the MIT License.
+ */
+package org.mockito.internal.configuration.plugins;
+
+import java.util.List;
+import org.mockito.plugins.AnnotationEngine;
+import org.mockito.plugins.DoNotMockChecker;
+import org.mockito.plugins.InstantiatorProvider2;
+import org.mockito.plugins.MemberAccessor;
+import org.mockito.plugins.MockMaker;
+import org.mockito.plugins.MockResolver;
+import org.mockito.plugins.MockitoLogger;
+import org.mockito.plugins.PluginSwitch;
+import org.mockito.plugins.StackTraceCleanerProvider;
+
+class PluginComponentRegistry {
+
+    private final PluginSwitch pluginToggle =
+            new PluginLoader(new DefaultPluginSwitch()).loadPlugin(PluginSwitch.class);
+
+    private final MockMaker mockFactory =
+            new PluginLoader(
+                pluginToggle,
+                            DefaultMockitoPluginRegistry.MOCK_MAKER_ALIASES.toArray(new String[0]))
+                    .loadPlugin(MockMaker.class);
+
+    private final MemberAccessor fieldAccessor =
+            new PluginLoader(
+                pluginToggle,
+                            DefaultMockitoPluginRegistry.MEMBER_ACCESSOR_ALIASES.toArray(new String[0]))
+                    .loadPlugin(MemberAccessor.class);
+
+    private final StackTraceCleanerProvider stackTraceCleanerFactory =
+            new PluginLoader(pluginToggle).loadPlugin(StackTraceCleanerProvider.class);
+
+    private final InstantiatorProvider2 instanceFactory;
+
+    private final AnnotationEngine annotationProcessor =
+            new PluginLoader(pluginToggle).loadPlugin(AnnotationEngine.class);
+
+    private final MockitoLogger frameworkLogger =
+            new PluginLoader(pluginToggle).loadPlugin(MockitoLogger.class);
+
+    private final List<MockResolver> resolverStrategies =
+            new PluginLoader(pluginToggle).loadPlugins(MockResolver.class);
+
+    private final DoNotMockChecker noMockValidator =
+            new PluginLoader(pluginToggle).loadPlugin(DoNotMockChecker.class);
+
+    PluginComponentRegistry() {
+        instanceFactory =
+                new PluginLoader(pluginToggle).loadPlugin(InstantiatorProvider2.class);
+    }
+
+    /**
+     * The implementation of the stack trace cleaner
+     */
+    StackTraceCleanerProvider getStackTraceCleanerProvider() {
+        // TODO we should throw some sensible exception if this is null.
+        return stackTraceCleanerFactory;
+    }
+
+    /**
+     * Returns the implementation of the mock maker available for the current runtime.
+     *
+     * <p>Returns {@link org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker} if no
+     * {@link org.mockito.plugins.MockMaker} extension exists or is visible in the current classpath.</p>
+     */
+    MockMaker getMockMaker() {
+        return mockFactory;
+    }
+
+    /**
+     * Returns the implementation of the member accessor available for the current runtime.
+     *
+     * <p>Returns {@link org.mockito.internal.util.reflection.ReflectionMemberAccessor} if no
+     * {@link org.mockito.plugins.MockMaker} extension exists or is visible in the current classpath.</p>
+     */
+    MemberAccessor getMemberAccessor() {
+        return fieldAccessor;
+    }
+
+    /**
+     * Returns the instantiator provider available for the current runtime.
+     *
+     * <p>Returns {@link org.mockito.internal.creation.instance.DefaultInstantiatorProvider} if no
+     * {@link org.mockito.plugins.InstantiatorProvider2} extension exists or is visible in the
+     * current classpath.</p>
+     */
+    InstantiatorProvider2 getInstantiatorProvider() {
+        return instanceFactory;
+    }
+
+    /**
+     * Returns the annotation engine available for the current runtime.
+     *
+     * <p>Returns {@link org.mockito.internal.configuration.InjectingAnnotationEngine} if no
+     * {@link org.mockito.plugins.AnnotationEngine} extension exists or is visible in the current classpath.</p>
+     */
+    AnnotationEngine getAnnotationEngine() {
+        return annotationProcessor;
+    }
+
+    /**
+     * Returns the logger available for the current runtime.
+     *
+     * <p>Returns {@link org.mockito.internal.util.ConsoleMockitoLogger} if no
+     * {@link org.mockito.plugins.MockitoLogger} extension exists or is visible in the current classpath.</p>
+     */
+    MockitoLogger getMockitoLogger() {
+        return frameworkLogger;
+    }
+
+    /**
+     * Returns the DoNotMock enforce for the current runtime.
+     *
+     * <p> Returns {@link org.mockito.internal.configuration.DefaultDoNotMockEnforcer} if no
+     * {@link DoNotMockChecker} extension exists or is visible in the current classpath.</p>
+     */
+    DoNotMockChecker getDoNotMockEnforcer() {
+        return noMockValidator;
+    }
+
+    /**
+     * Returns a list of available mock resolvers if any.
+     *
+     * @return A list of available mock resolvers or an empty list if none are registered.
+     */
+    List<MockResolver> getMockResolvers() {
+        return resolverStrategies;
+    }
+}
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
index 72f5d8e7d..7727cc051 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/PluginRegistry.java
@@ -4,82 +4,48 @@
  */
 package org.mockito.internal.configuration.plugins;
 
+import org.mockito.DoNotMock;
 import java.util.List;
 import org.mockito.plugins.AnnotationEngine;
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.plugins.DoNotMockChecker;
 import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockResolver;
 import org.mockito.plugins.MockitoLogger;
-import org.mockito.plugins.PluginSwitch;
+import org.mockito.plugins.MockitoPlugins;
 import org.mockito.plugins.StackTraceCleanerProvider;
 
-class PluginRegistry {
+/** Access to Mockito behavior that can be reconfigured by plugins */
+public final class PluginRegistry {
 
-    private final PluginSwitch pluginSwitch =
-            new PluginLoader(new DefaultPluginSwitch()).loadPlugin(PluginSwitch.class);
-
-    private final MockMaker mockMaker =
-            new PluginLoader(
-                            pluginSwitch,
-                            DefaultMockitoPlugins.MOCK_MAKER_ALIASES.toArray(new String[0]))
-                    .loadPlugin(MockMaker.class);
-
-    private final MemberAccessor memberAccessor =
-            new PluginLoader(
-                            pluginSwitch,
-                            DefaultMockitoPlugins.MEMBER_ACCESSOR_ALIASES.toArray(new String[0]))
-                    .loadPlugin(MemberAccessor.class);
-
-    private final StackTraceCleanerProvider stackTraceCleanerProvider =
-            new PluginLoader(pluginSwitch).loadPlugin(StackTraceCleanerProvider.class);
-
-    private final InstantiatorProvider2 instantiatorProvider;
-
-    private final AnnotationEngine annotationEngine =
-            new PluginLoader(pluginSwitch).loadPlugin(AnnotationEngine.class);
-
-    private final MockitoLogger mockitoLogger =
-            new PluginLoader(pluginSwitch).loadPlugin(MockitoLogger.class);
-
-    private final List<MockResolver> mockResolvers =
-            new PluginLoader(pluginSwitch).loadPlugins(MockResolver.class);
-
-    private final DoNotMockEnforcer doNotMockEnforcer =
-            new PluginLoader(pluginSwitch).loadPlugin(DoNotMockEnforcer.class);
-
-    PluginRegistry() {
-        instantiatorProvider =
-                new PluginLoader(pluginSwitch).loadPlugin(InstantiatorProvider2.class);
-    }
+    private static final PluginComponentRegistry PLUGIN_COMPONENT_REPOSITORY = new PluginComponentRegistry();
 
     /**
      * The implementation of the stack trace cleaner
      */
-    StackTraceCleanerProvider getStackTraceCleanerProvider() {
-        // TODO we should throw some sensible exception if this is null.
-        return stackTraceCleanerProvider;
+    public static StackTraceCleanerProvider getStackTraceCleanerProvider() {
+        return PLUGIN_COMPONENT_REPOSITORY.getStackTraceCleanerProvider();
     }
 
     /**
      * Returns the implementation of the mock maker available for the current runtime.
      *
-     * <p>Returns {@link org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker} if no
+     * <p>Returns default mock maker if no
      * {@link org.mockito.plugins.MockMaker} extension exists or is visible in the current classpath.</p>
      */
-    MockMaker getMockMaker() {
-        return mockMaker;
+    public static MockMaker getMockMaker() {
+        return PLUGIN_COMPONENT_REPOSITORY.getMockMaker();
     }
 
     /**
      * Returns the implementation of the member accessor available for the current runtime.
      *
-     * <p>Returns {@link org.mockito.internal.util.reflection.ReflectionMemberAccessor} if no
-     * {@link org.mockito.plugins.MockMaker} extension exists or is visible in the current classpath.</p>
+     * <p>Returns default member accessor if no
+     * {@link org.mockito.plugins.MemberAccessor} extension exists or is visible in the current classpath.</p>
      */
-    MemberAccessor getMemberAccessor() {
-        return memberAccessor;
+    public static MemberAccessor getMemberAccessor() {
+        return PLUGIN_COMPONENT_REPOSITORY.getMemberAccessor();
     }
 
     /**
@@ -89,8 +55,8 @@ class PluginRegistry {
      * {@link org.mockito.plugins.InstantiatorProvider2} extension exists or is visible in the
      * current classpath.</p>
      */
-    InstantiatorProvider2 getInstantiatorProvider() {
-        return instantiatorProvider;
+    public static InstantiatorProvider2 getInstantiatorProvider() {
+        return PLUGIN_COMPONENT_REPOSITORY.getInstantiatorProvider();
     }
 
     /**
@@ -99,8 +65,8 @@ class PluginRegistry {
      * <p>Returns {@link org.mockito.internal.configuration.InjectingAnnotationEngine} if no
      * {@link org.mockito.plugins.AnnotationEngine} extension exists or is visible in the current classpath.</p>
      */
-    AnnotationEngine getAnnotationEngine() {
-        return annotationEngine;
+    public static AnnotationEngine getAnnotationEngine() {
+        return PLUGIN_COMPONENT_REPOSITORY.getAnnotationEngine();
     }
 
     /**
@@ -109,26 +75,35 @@ class PluginRegistry {
      * <p>Returns {@link org.mockito.internal.util.ConsoleMockitoLogger} if no
      * {@link org.mockito.plugins.MockitoLogger} extension exists or is visible in the current classpath.</p>
      */
-    MockitoLogger getMockitoLogger() {
-        return mockitoLogger;
+    public static MockitoLogger getMockitoLogger() {
+        return PLUGIN_COMPONENT_REPOSITORY.getMockitoLogger();
     }
 
     /**
-     * Returns the DoNotMock enforce for the current runtime.
+     * Returns a list of available mock resolvers if any.
      *
-     * <p> Returns {@link org.mockito.internal.configuration.DefaultDoNotMockEnforcer} if no
-     * {@link DoNotMockEnforcer} extension exists or is visible in the current classpath.</p>
+     * @return A list of available mock resolvers or an empty list if none are registered.
      */
-    DoNotMockEnforcer getDoNotMockEnforcer() {
-        return doNotMockEnforcer;
+    public static List<MockResolver> getMockResolvers() {
+        return PLUGIN_COMPONENT_REPOSITORY.getMockResolvers();
     }
 
     /**
-     * Returns a list of available mock resolvers if any.
+     * @return instance of mockito plugins type
+     */
+    public static MockitoPlugins getPlugins() {
+        return new DefaultMockitoPluginRegistry();
+    }
+
+    /**
+     * Returns the {@link DoNotMock} enforcer available for the current runtime.
      *
-     * @return A list of available mock resolvers or an empty list if none are registered.
+     * <p> Returns {@link org.mockito.internal.configuration.DefaultDoNotMockEnforcer} if no
+     * {@link DoNotMockChecker} extension exists or is visible in the current classpath.</p>
      */
-    List<MockResolver> getMockResolvers() {
-        return mockResolvers;
+    public static DoNotMockChecker getDoNotMockEnforcer() {
+        return PLUGIN_COMPONENT_REPOSITORY.getDoNotMockEnforcer();
     }
+
+    private PluginRegistry() {}
 }
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java b/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
deleted file mode 100644
index 20f6dc7bc..000000000
--- a/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
+++ /dev/null
@@ -1,109 +0,0 @@
-/*
- * Copyright (c) 2016 Mockito contributors
- * This program is made available under the terms of the MIT License.
- */
-package org.mockito.internal.configuration.plugins;
-
-import org.mockito.DoNotMock;
-import java.util.List;
-import org.mockito.plugins.AnnotationEngine;
-import org.mockito.plugins.DoNotMockEnforcer;
-import org.mockito.plugins.InstantiatorProvider2;
-import org.mockito.plugins.MemberAccessor;
-import org.mockito.plugins.MockMaker;
-import org.mockito.plugins.MockResolver;
-import org.mockito.plugins.MockitoLogger;
-import org.mockito.plugins.MockitoPlugins;
-import org.mockito.plugins.StackTraceCleanerProvider;
-
-/** Access to Mockito behavior that can be reconfigured by plugins */
-public final class Plugins {
-
-    private static final PluginRegistry registry = new PluginRegistry();
-
-    /**
-     * The implementation of the stack trace cleaner
-     */
-    public static StackTraceCleanerProvider getStackTraceCleanerProvider() {
-        return registry.getStackTraceCleanerProvider();
-    }
-
-    /**
-     * Returns the implementation of the mock maker available for the current runtime.
-     *
-     * <p>Returns default mock maker if no
-     * {@link org.mockito.plugins.MockMaker} extension exists or is visible in the current classpath.</p>
-     */
-    public static MockMaker getMockMaker() {
-        return registry.getMockMaker();
-    }
-
-    /**
-     * Returns the implementation of the member accessor available for the current runtime.
-     *
-     * <p>Returns default member accessor if no
-     * {@link org.mockito.plugins.MemberAccessor} extension exists or is visible in the current classpath.</p>
-     */
-    public static MemberAccessor getMemberAccessor() {
-        return registry.getMemberAccessor();
-    }
-
-    /**
-     * Returns the instantiator provider available for the current runtime.
-     *
-     * <p>Returns {@link org.mockito.internal.creation.instance.DefaultInstantiatorProvider} if no
-     * {@link org.mockito.plugins.InstantiatorProvider2} extension exists or is visible in the
-     * current classpath.</p>
-     */
-    public static InstantiatorProvider2 getInstantiatorProvider() {
-        return registry.getInstantiatorProvider();
-    }
-
-    /**
-     * Returns the annotation engine available for the current runtime.
-     *
-     * <p>Returns {@link org.mockito.internal.configuration.InjectingAnnotationEngine} if no
-     * {@link org.mockito.plugins.AnnotationEngine} extension exists or is visible in the current classpath.</p>
-     */
-    public static AnnotationEngine getAnnotationEngine() {
-        return registry.getAnnotationEngine();
-    }
-
-    /**
-     * Returns the logger available for the current runtime.
-     *
-     * <p>Returns {@link org.mockito.internal.util.ConsoleMockitoLogger} if no
-     * {@link org.mockito.plugins.MockitoLogger} extension exists or is visible in the current classpath.</p>
-     */
-    public static MockitoLogger getMockitoLogger() {
-        return registry.getMockitoLogger();
-    }
-
-    /**
-     * Returns a list of available mock resolvers if any.
-     *
-     * @return A list of available mock resolvers or an empty list if none are registered.
-     */
-    public static List<MockResolver> getMockResolvers() {
-        return registry.getMockResolvers();
-    }
-
-    /**
-     * @return instance of mockito plugins type
-     */
-    public static MockitoPlugins getPlugins() {
-        return new DefaultMockitoPlugins();
-    }
-
-    /**
-     * Returns the {@link DoNotMock} enforcer available for the current runtime.
-     *
-     * <p> Returns {@link org.mockito.internal.configuration.DefaultDoNotMockEnforcer} if no
-     * {@link DoNotMockEnforcer} extension exists or is visible in the current classpath.</p>
-     */
-    public static DoNotMockEnforcer getDoNotMockEnforcer() {
-        return registry.getDoNotMockEnforcer();
-    }
-
-    private Plugins() {}
-}
diff --git a/src/main/java/org/mockito/internal/creation/DefaultMockSettings.java b/src/main/java/org/mockito/internal/creation/DefaultMockSettings.java
new file mode 100644
index 000000000..5ebcd1638
--- /dev/null
+++ b/src/main/java/org/mockito/internal/creation/DefaultMockSettings.java
@@ -0,0 +1,322 @@
+/*
+ * Copyright (c) 2007 Mockito contributors
+ * This program is made available under the terms of the MIT License.
+ */
+package org.mockito.internal.creation;
+
+import static java.util.Arrays.asList;
+
+import static org.mockito.internal.exceptions.Reporter.defaultAnswerDoesNotAcceptNullParameter;
+import static org.mockito.internal.exceptions.Reporter.extraInterfacesAcceptsOnlyInterfaces;
+import static org.mockito.internal.exceptions.Reporter.extraInterfacesDoesNotAcceptNullParameters;
+import static org.mockito.internal.exceptions.Reporter.extraInterfacesRequiresAtLeastOneInterface;
+import static org.mockito.internal.exceptions.Reporter.methodDoesNotAcceptParameter;
+import static org.mockito.internal.exceptions.Reporter.requiresAtLeastOneListener;
+import static org.mockito.internal.exceptions.Reporter.strictnessDoesNotAcceptNullParameter;
+import static org.mockito.internal.util.collections.Sets.newSet;
+
+import java.io.Serializable;
+import java.lang.reflect.Type;
+import java.util.ArrayList;
+import java.util.HashSet;
+import java.util.List;
+import java.util.Set;
+
+import org.mockito.MockSettings;
+import org.mockito.exceptions.base.MockitoException;
+import org.mockito.internal.creation.settings.MockCreationSettings;
+import org.mockito.internal.debugging.VerboseMockInvocationLogger;
+import org.mockito.internal.util.Checks;
+import org.mockito.internal.util.MockCreationValidator;
+import org.mockito.internal.util.MockNameImplementation;
+import org.mockito.listeners.InvocationListener;
+import org.mockito.listeners.StubbingLookupListener;
+import org.mockito.listeners.VerificationStartedListener;
+import org.mockito.mock.MockCreationOptions;
+import org.mockito.mock.MockName;
+import org.mockito.mock.SerializableMode;
+import org.mockito.quality.Strictness;
+import org.mockito.stubbing.Answer;
+
+@SuppressWarnings("unchecked")
+public class DefaultMockSettings<T> extends MockCreationSettings<T>
+        implements MockSettings, MockCreationOptions<T> {
+
+    private static final long SERIAL_VERSION_ID = 4475297236197939569L;
+    private boolean useCtor;
+    private Object outerInstance;
+    private Object[] constructorParameters;
+
+    @Override
+    public MockSettings serializable() {
+        return serializable(SerializableMode.BASIC);
+    }
+
+    @Override
+    public MockSettings serializable(SerializableMode serializableMode) {
+        this.serializableMode = serializableMode;
+        return this;
+    }
+
+    @Override
+    public MockSettings extraInterfaces(Class<?>... additionalInterfaces) {
+        if (additionalInterfaces == null || additionalInterfaces.length == 0) {
+            throw extraInterfacesRequiresAtLeastOneInterface();
+        }
+
+        for (Class<?> iface : additionalInterfaces) {
+            if (iface == null) {
+                throw extraInterfacesDoesNotAcceptNullParameters();
+            } else if (!iface.isInterface()) {
+                throw extraInterfacesAcceptsOnlyInterfaces(iface);
+            }
+        }
+        this.extraInterfaces = newSet(additionalInterfaces);
+        return this;
+    }
+
+    @Override
+    public MockName getMockName() {
+        return mockName;
+    }
+
+    @Override
+    public Set<Class<?>> getExtraInterfaces() {
+        return extraInterfaces;
+    }
+
+    @Override
+    public Object getSpiedInstance() {
+        return spiedInstance;
+    }
+
+    @Override
+    public MockSettings name(String mockName) {
+        this.name = mockName;
+        return this;
+    }
+
+    @Override
+    public MockSettings spiedInstance(Object spyInstance) {
+        this.spiedInstance = spyInstance;
+        return this;
+    }
+
+    @Override
+    public MockSettings defaultAnswer(Answer defaultResponse) {
+        this.defaultAnswer = defaultResponse;
+        if (defaultResponse == null) {
+            throw defaultAnswerDoesNotAcceptNullParameter();
+        }
+        return this;
+    }
+
+    @Override
+    public Answer<Object> getDefaultAnswer() {
+        return defaultAnswer;
+    }
+
+    @Override
+    public DefaultMockSettings<T> stubOnly() {
+        this.stubOnly = true;
+        return this;
+    }
+
+    @Override
+    public MockSettings useConstructor(Object... constructorParameters) {
+        Checks.checkNotNull(
+            constructorParameters,
+                "constructorArgs",
+                "If you need to pass null, please cast it to the right type, e.g.: useConstructor((String) null)");
+        this.useCtor = true;
+        this.constructorParameters = constructorParameters;
+        return this;
+    }
+
+    @Override
+    public MockSettings outerInstance(Object outerInstance) {
+        this.outerInstance = outerInstance;
+        return this;
+    }
+
+    @Override
+    public MockSettings withoutAnnotations() {
+        stripAnnotations = true;
+        return this;
+    }
+
+    @Override
+    public boolean isUsingConstructor() {
+        return useCtor;
+    }
+
+    @Override
+    public Object getOuterClassInstance() {
+        return outerInstance;
+    }
+
+    @Override
+    public Object[] getConstructorArgs() {
+        if (outerInstance == null) {
+            return constructorParameters;
+        }
+        List<Object> resultList = new ArrayList<>(constructorParameters.length + 1);
+        resultList.add(outerInstance);
+        resultList.addAll(asList(constructorParameters));
+        return resultList.toArray(new Object[constructorParameters.length + 1]);
+    }
+
+    @Override
+    public boolean isStubOnly() {
+        return this.stubOnly;
+    }
+
+    @Override
+    public MockSettings verboseLogging() {
+        if (!containsInvocationListenerOfType(VerboseMockInvocationLogger.class)) {
+            invocationListeners(new VerboseMockInvocationLogger());
+        }
+        return this;
+    }
+
+    @Override
+    public MockSettings invocationListeners(InvocationListener... invocationListeners) {
+        addListener(invocationListeners, this.invocationListeners, "invocationListeners");
+        return this;
+    }
+
+    @Override
+    public MockSettings stubbingLookupListeners(StubbingLookupListener... invocationListeners) {
+        addListener(invocationListeners, stubbingLookupListeners, "stubbingLookupListeners");
+        return this;
+    }
+
+    static <T> void addListener(T[] invocationListeners, List<T> containerList, String methodName) {
+        if (invocationListeners == null) {
+            throw methodDoesNotAcceptParameter(methodName, "null vararg array.");
+        }
+        if (invocationListeners.length == 0) {
+            throw requiresAtLeastOneListener(methodName);
+        }
+        for (T newListener : invocationListeners) {
+            if (newListener == null) {
+                throw methodDoesNotAcceptParameter(methodName, "null listeners.");
+            }
+            containerList.add(newListener);
+        }
+    }
+
+    @Override
+    public MockSettings verificationStartedListeners(VerificationStartedListener... invocationListeners) {
+        addListener(invocationListeners, this.verificationStartedListeners, "verificationStartedListeners");
+        return this;
+    }
+
+    private boolean containsInvocationListenerOfType(Class<?> listenerType) {
+        for (InvocationListener newListener : invocationListeners) {
+            if (newListener.getClass().equals(listenerType)) {
+                return true;
+            }
+        }
+        return false;
+    }
+
+    public boolean hasAnyInvocationListeners() {
+        return !getInvocationListeners().isEmpty();
+    }
+
+    @Override
+    public Class<T> getTypeToMock() {
+        return typeToMock;
+    }
+
+    @Override
+    public <T2> MockCreationOptions<T2> build(Class<T2> targetType) {
+        return createValidatedSettings(targetType, (MockCreationSettings<T2>) this);
+    }
+
+    @Override
+    public <T2> MockCreationOptions<T2> buildStatic(Class<T2> targetClass) {
+        return createValidatedStaticSettings(targetClass, (MockCreationSettings<T2>) this);
+    }
+
+    @Override
+    public MockSettings lenient() {
+        this.strictness = Strictness.LENIENT;
+        return this;
+    }
+
+    @Override
+    public MockSettings strictness(Strictness mockStrictness) {
+        if (mockStrictness == null) {
+            throw strictnessDoesNotAcceptNullParameter();
+        }
+        this.strictness = mockStrictness;
+        return this;
+    }
+
+    @Override
+    public MockSettings mockMaker(String mockMakerName) {
+        this.mockMaker = mockMakerName;
+        return this;
+    }
+
+    @Override
+    public MockSettings genericTypeToMock(Type genericTypeParam) {
+        this.genericTypeToMock = genericTypeParam;
+        return this;
+    }
+
+    private static <T> MockCreationSettings<T> createValidatedSettings(
+        Class<T> targetType, MockCreationSettings<T> sourceSettings) {
+        MockCreationValidator validatorInstance = new MockCreationValidator();
+
+        validatorInstance.validateType(targetType, sourceSettings.getMockMaker());
+        validatorInstance.validateExtraInterfaces(targetType, sourceSettings.getExtraInterfaces());
+        validatorInstance.validateMockedType(targetType, sourceSettings.getSpiedInstance());
+
+        // TODO SF - add this validation and also add missing coverage
+        //        validator.validateDelegatedInstance(classToMock, settings.getDelegatedInstance());
+
+        validatorInstance.validateConstructorUse(sourceSettings.isUsingConstructor(), sourceSettings.getSerializableMode());
+
+        // TODO SF - I don't think we really need CreationSettings type
+        // TODO do we really need to copy the entire settings every time we create mock object? it
+        // does not seem necessary.
+        MockCreationSettings<T> creationSettings = new MockCreationSettings<T>(sourceSettings);
+        creationSettings.setMockName(new MockNameImplementation(sourceSettings.getName(), targetType, false));
+        creationSettings.setTypeToMock(targetType);
+        creationSettings.setExtraInterfaces(collectExtraInterfaces(sourceSettings));
+        return creationSettings;
+    }
+
+    private static <T> MockCreationSettings<T> createValidatedStaticSettings(
+        Class<T> targetClass, MockCreationSettings<T> sourceSettings) {
+
+        if (targetClass.isPrimitive()) {
+            throw new MockitoException(
+                    "Cannot create static mock of primitive type " + targetClass);
+        }
+        if (!sourceSettings.getExtraInterfaces().isEmpty()) {
+            throw new MockitoException(
+                    "Cannot specify additional interfaces for static mock of " + targetClass);
+        }
+        if (sourceSettings.getSpiedInstance() != null) {
+            throw new MockitoException(
+                    "Cannot specify spied instance for static mock of " + targetClass);
+        }
+
+        MockCreationSettings<T> creationSettings = new MockCreationSettings<T>(sourceSettings);
+        creationSettings.setMockName(new MockNameImplementation(sourceSettings.getName(), targetClass, true));
+        creationSettings.setTypeToMock(targetClass);
+        return creationSettings;
+    }
+
+    private static Set<Class<?>> collectExtraInterfaces(MockCreationSettings creationSettings) {
+        Set<Class<?>> interfacesSet = new HashSet<>(creationSettings.getExtraInterfaces());
+        if (creationSettings.isSerializable()) {
+            interfacesSet.add(Serializable.class);
+        }
+        return interfacesSet;
+    }
+}
diff --git a/src/main/java/org/mockito/internal/creation/MockSettingsImpl.java b/src/main/java/org/mockito/internal/creation/MockSettingsImpl.java
deleted file mode 100644
index 7bef7764d..000000000
--- a/src/main/java/org/mockito/internal/creation/MockSettingsImpl.java
+++ /dev/null
@@ -1,322 +0,0 @@
-/*
- * Copyright (c) 2007 Mockito contributors
- * This program is made available under the terms of the MIT License.
- */
-package org.mockito.internal.creation;
-
-import static java.util.Arrays.asList;
-
-import static org.mockito.internal.exceptions.Reporter.defaultAnswerDoesNotAcceptNullParameter;
-import static org.mockito.internal.exceptions.Reporter.extraInterfacesAcceptsOnlyInterfaces;
-import static org.mockito.internal.exceptions.Reporter.extraInterfacesDoesNotAcceptNullParameters;
-import static org.mockito.internal.exceptions.Reporter.extraInterfacesRequiresAtLeastOneInterface;
-import static org.mockito.internal.exceptions.Reporter.methodDoesNotAcceptParameter;
-import static org.mockito.internal.exceptions.Reporter.requiresAtLeastOneListener;
-import static org.mockito.internal.exceptions.Reporter.strictnessDoesNotAcceptNullParameter;
-import static org.mockito.internal.util.collections.Sets.newSet;
-
-import java.io.Serializable;
-import java.lang.reflect.Type;
-import java.util.ArrayList;
-import java.util.HashSet;
-import java.util.List;
-import java.util.Set;
-
-import org.mockito.MockSettings;
-import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.creation.settings.CreationSettings;
-import org.mockito.internal.debugging.VerboseMockInvocationLogger;
-import org.mockito.internal.util.Checks;
-import org.mockito.internal.util.MockCreationValidator;
-import org.mockito.internal.util.MockNameImpl;
-import org.mockito.listeners.InvocationListener;
-import org.mockito.listeners.StubbingLookupListener;
-import org.mockito.listeners.VerificationStartedListener;
-import org.mockito.mock.MockCreationSettings;
-import org.mockito.mock.MockName;
-import org.mockito.mock.SerializableMode;
-import org.mockito.quality.Strictness;
-import org.mockito.stubbing.Answer;
-
-@SuppressWarnings("unchecked")
-public class MockSettingsImpl<T> extends CreationSettings<T>
-        implements MockSettings, MockCreationSettings<T> {
-
-    private static final long serialVersionUID = 4475297236197939569L;
-    private boolean useConstructor;
-    private Object outerClassInstance;
-    private Object[] constructorArgs;
-
-    @Override
-    public MockSettings serializable() {
-        return serializable(SerializableMode.BASIC);
-    }
-
-    @Override
-    public MockSettings serializable(SerializableMode mode) {
-        this.serializableMode = mode;
-        return this;
-    }
-
-    @Override
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
-        }
-        this.extraInterfaces = newSet(extraInterfaces);
-        return this;
-    }
-
-    @Override
-    public MockName getMockName() {
-        return mockName;
-    }
-
-    @Override
-    public Set<Class<?>> getExtraInterfaces() {
-        return extraInterfaces;
-    }
-
-    @Override
-    public Object getSpiedInstance() {
-        return spiedInstance;
-    }
-
-    @Override
-    public MockSettings name(String name) {
-        this.name = name;
-        return this;
-    }
-
-    @Override
-    public MockSettings spiedInstance(Object spiedInstance) {
-        this.spiedInstance = spiedInstance;
-        return this;
-    }
-
-    @Override
-    public MockSettings defaultAnswer(Answer defaultAnswer) {
-        this.defaultAnswer = defaultAnswer;
-        if (defaultAnswer == null) {
-            throw defaultAnswerDoesNotAcceptNullParameter();
-        }
-        return this;
-    }
-
-    @Override
-    public Answer<Object> getDefaultAnswer() {
-        return defaultAnswer;
-    }
-
-    @Override
-    public MockSettingsImpl<T> stubOnly() {
-        this.stubOnly = true;
-        return this;
-    }
-
-    @Override
-    public MockSettings useConstructor(Object... constructorArgs) {
-        Checks.checkNotNull(
-                constructorArgs,
-                "constructorArgs",
-                "If you need to pass null, please cast it to the right type, e.g.: useConstructor((String) null)");
-        this.useConstructor = true;
-        this.constructorArgs = constructorArgs;
-        return this;
-    }
-
-    @Override
-    public MockSettings outerInstance(Object outerClassInstance) {
-        this.outerClassInstance = outerClassInstance;
-        return this;
-    }
-
-    @Override
-    public MockSettings withoutAnnotations() {
-        stripAnnotations = true;
-        return this;
-    }
-
-    @Override
-    public boolean isUsingConstructor() {
-        return useConstructor;
-    }
-
-    @Override
-    public Object getOuterClassInstance() {
-        return outerClassInstance;
-    }
-
-    @Override
-    public Object[] getConstructorArgs() {
-        if (outerClassInstance == null) {
-            return constructorArgs;
-        }
-        List<Object> resultArgs = new ArrayList<>(constructorArgs.length + 1);
-        resultArgs.add(outerClassInstance);
-        resultArgs.addAll(asList(constructorArgs));
-        return resultArgs.toArray(new Object[constructorArgs.length + 1]);
-    }
-
-    @Override
-    public boolean isStubOnly() {
-        return this.stubOnly;
-    }
-
-    @Override
-    public MockSettings verboseLogging() {
-        if (!invocationListenersContainsType(VerboseMockInvocationLogger.class)) {
-            invocationListeners(new VerboseMockInvocationLogger());
-        }
-        return this;
-    }
-
-    @Override
-    public MockSettings invocationListeners(InvocationListener... listeners) {
-        addListeners(listeners, invocationListeners, "invocationListeners");
-        return this;
-    }
-
-    @Override
-    public MockSettings stubbingLookupListeners(StubbingLookupListener... listeners) {
-        addListeners(listeners, stubbingLookupListeners, "stubbingLookupListeners");
-        return this;
-    }
-
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
-    }
-
-    @Override
-    public MockSettings verificationStartedListeners(VerificationStartedListener... listeners) {
-        addListeners(listeners, this.verificationStartedListeners, "verificationStartedListeners");
-        return this;
-    }
-
-    private boolean invocationListenersContainsType(Class<?> clazz) {
-        for (InvocationListener listener : invocationListeners) {
-            if (listener.getClass().equals(clazz)) {
-                return true;
-            }
-        }
-        return false;
-    }
-
-    public boolean hasInvocationListeners() {
-        return !getInvocationListeners().isEmpty();
-    }
-
-    @Override
-    public Class<T> getTypeToMock() {
-        return typeToMock;
-    }
-
-    @Override
-    public <T2> MockCreationSettings<T2> build(Class<T2> typeToMock) {
-        return validatedSettings(typeToMock, (CreationSettings<T2>) this);
-    }
-
-    @Override
-    public <T2> MockCreationSettings<T2> buildStatic(Class<T2> classToMock) {
-        return validatedStaticSettings(classToMock, (CreationSettings<T2>) this);
-    }
-
-    @Override
-    public MockSettings lenient() {
-        this.strictness = Strictness.LENIENT;
-        return this;
-    }
-
-    @Override
-    public MockSettings strictness(Strictness strictness) {
-        if (strictness == null) {
-            throw strictnessDoesNotAcceptNullParameter();
-        }
-        this.strictness = strictness;
-        return this;
-    }
-
-    @Override
-    public MockSettings mockMaker(String mockMaker) {
-        this.mockMaker = mockMaker;
-        return this;
-    }
-
-    @Override
-    public MockSettings genericTypeToMock(Type genericType) {
-        this.genericTypeToMock = genericType;
-        return this;
-    }
-
-    private static <T> CreationSettings<T> validatedSettings(
-            Class<T> typeToMock, CreationSettings<T> source) {
-        MockCreationValidator validator = new MockCreationValidator();
-
-        validator.validateType(typeToMock, source.getMockMaker());
-        validator.validateExtraInterfaces(typeToMock, source.getExtraInterfaces());
-        validator.validateMockedType(typeToMock, source.getSpiedInstance());
-
-        // TODO SF - add this validation and also add missing coverage
-        //        validator.validateDelegatedInstance(classToMock, settings.getDelegatedInstance());
-
-        validator.validateConstructorUse(source.isUsingConstructor(), source.getSerializableMode());
-
-        // TODO SF - I don't think we really need CreationSettings type
-        // TODO do we really need to copy the entire settings every time we create mock object? it
-        // does not seem necessary.
-        CreationSettings<T> settings = new CreationSettings<T>(source);
-        settings.setMockName(new MockNameImpl(source.getName(), typeToMock, false));
-        settings.setTypeToMock(typeToMock);
-        settings.setExtraInterfaces(prepareExtraInterfaces(source));
-        return settings;
-    }
-
-    private static <T> CreationSettings<T> validatedStaticSettings(
-            Class<T> classToMock, CreationSettings<T> source) {
-
-        if (classToMock.isPrimitive()) {
-            throw new MockitoException(
-                    "Cannot create static mock of primitive type " + classToMock);
-        }
-        if (!source.getExtraInterfaces().isEmpty()) {
-            throw new MockitoException(
-                    "Cannot specify additional interfaces for static mock of " + classToMock);
-        }
-        if (source.getSpiedInstance() != null) {
-            throw new MockitoException(
-                    "Cannot specify spied instance for static mock of " + classToMock);
-        }
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
-        }
-        return interfaces;
-    }
-}
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
index a1eed21e7..8fdfe2eda 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
@@ -22,10 +22,10 @@ import java.util.concurrent.locks.Lock;
 import java.util.concurrent.locks.ReentrantLock;
 
 import org.mockito.exceptions.base.MockitoSerializationIssue;
-import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.internal.util.MockUtil;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.mock.MockName;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MemberAccessor;
@@ -185,7 +185,7 @@ class ByteBuddyCrossClassLoaderSerializationSupport implements Serializable {
             objectOutputStream.close();
             out.close();
 
-            MockCreationSettings<?> mockSettings = MockUtil.getMockSettings(mockitoMock);
+            MockCreationOptions<?> mockSettings = MockUtil.getMockSettings(mockitoMock);
             this.serializedMock = out.toByteArray();
             this.typeToMock = mockSettings.getTypeToMock();
             this.extraInterfaces = mockSettings.getExtraInterfaces();
@@ -244,7 +244,7 @@ class ByteBuddyCrossClassLoaderSerializationSupport implements Serializable {
      * </p>
      * <p/>
      * <p>
-     *     When this marker is found, {@link ByteBuddyMockMaker#createMockType(MockCreationSettings)} methods are being used
+     *     When this marker is found, {@link ByteBuddyMockMaker#createMockType(MockCreationOptions)} methods are being used
      *     to create the mock class.
      * </p>
      */
@@ -285,9 +285,9 @@ class ByteBuddyCrossClassLoaderSerializationSupport implements Serializable {
             try {
                 @SuppressWarnings("unchecked")
                 Class<?> proxyClass =
-                        ((ClassCreatingMockMaker) Plugins.getMockMaker())
+                        ((ClassCreatingMockMaker) PluginRegistry.getMockMaker())
                                 .createMockType(
-                                        new CreationSettings()
+                                        new MockCreationSettings()
                                                 .setTypeToMock(typeToMock)
                                                 .setExtraInterfaces(extraInterfaces)
                                                 .setSerializableMode(
@@ -300,7 +300,7 @@ class ByteBuddyCrossClassLoaderSerializationSupport implements Serializable {
                         join(
                                 "A Byte Buddy-generated mock cannot be deserialized into a non-Byte Buddy generated mock class",
                                 "",
-                                "The mock maker in use was: " + Plugins.getMockMaker().getClass()),
+                                "The mock maker in use was: " + PluginRegistry.getMockMaker().getClass()),
                         cce);
             }
         }
@@ -326,7 +326,7 @@ class ByteBuddyCrossClassLoaderSerializationSupport implements Serializable {
         private void hackClassNameToMatchNewlyCreatedClass(
                 ObjectStreamClass descInstance, Class<?> proxyClass) throws ObjectStreamException {
             try {
-                MemberAccessor accessor = Plugins.getMemberAccessor();
+                MemberAccessor accessor = PluginRegistry.getMemberAccessor();
                 Field classNameField = descInstance.getClass().getDeclaredField("name");
                 try {
                     accessor.set(classNameField, descInstance, proxyClass.getCanonicalName());
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMaker.java
index 9a836bbbb..cf9e76933 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMaker.java
@@ -7,7 +7,7 @@ package org.mockito.internal.creation.bytebuddy;
 import org.mockito.MockedConstruction;
 import org.mockito.internal.exceptions.Reporter;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 import java.util.Optional;
 import java.util.function.Function;
@@ -37,18 +37,18 @@ public class ByteBuddyMockMaker implements ClassCreatingMockMaker {
     }
 
     @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+    public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
         return subclassByteBuddyMockMaker.createMock(settings, handler);
     }
 
     @Override
     public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T object) {
+        MockCreationOptions<T> settings, MockHandler handler, T object) {
         return subclassByteBuddyMockMaker.createSpy(settings, handler, object);
     }
 
     @Override
-    public <T> Class<? extends T> createMockType(MockCreationSettings<T> creationSettings) {
+    public <T> Class<? extends T> createMockType(MockCreationOptions<T> creationSettings) {
         return subclassByteBuddyMockMaker.createMockType(creationSettings);
     }
 
@@ -58,7 +58,7 @@ public class ByteBuddyMockMaker implements ClassCreatingMockMaker {
     }
 
     @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+    public void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings) {
         subclassByteBuddyMockMaker.resetMock(mock, newHandler, settings);
     }
 
@@ -69,14 +69,14 @@ public class ByteBuddyMockMaker implements ClassCreatingMockMaker {
 
     @Override
     public <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
+        Class<T> type, MockCreationOptions<T> settings, MockHandler handler) {
         return subclassByteBuddyMockMaker.createStaticMock(type, settings, handler);
     }
 
     @Override
     public <T> ConstructionMockControl<T> createConstructionMock(
             Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
+            Function<MockedConstruction.Context, MockCreationOptions<T>> settingsFactory,
             Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
             MockedConstruction.MockInitializer<T> mockInitializer) {
         return subclassByteBuddyMockMaker.createConstructionMock(
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/ClassCreatingMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ClassCreatingMockMaker.java
index b6f9b3f89..fde45e616 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/ClassCreatingMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ClassCreatingMockMaker.java
@@ -4,9 +4,9 @@
  */
 package org.mockito.internal.creation.bytebuddy;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.MockMaker;
 
 interface ClassCreatingMockMaker extends MockMaker {
-    <T> Class<? extends T> createMockType(MockCreationSettings<T> settings);
+    <T> Class<? extends T> createMockType(MockCreationOptions<T> settings);
 }
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
index acfddfef3..876798141 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMaker.java
@@ -8,7 +8,7 @@ import org.mockito.MockedConstruction;
 import org.mockito.creation.instance.Instantiator;
 import org.mockito.internal.exceptions.Reporter;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.InlineMockMaker;
 
 import java.util.Optional;
@@ -37,7 +37,7 @@ public class InlineByteBuddyMockMaker
     }
 
     @Override
-    public <T> Class<? extends T> createMockType(MockCreationSettings<T> settings) {
+    public <T> Class<? extends T> createMockType(MockCreationOptions<T> settings) {
         return inlineDelegateByteBuddyMockMaker.createMockType(settings);
     }
 
@@ -52,13 +52,13 @@ public class InlineByteBuddyMockMaker
     }
 
     @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+    public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
         return inlineDelegateByteBuddyMockMaker.createMock(settings, handler);
     }
 
     @Override
     public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T instance) {
+        MockCreationOptions<T> settings, MockHandler handler, T instance) {
         return inlineDelegateByteBuddyMockMaker.createSpy(settings, handler, instance);
     }
 
@@ -68,7 +68,7 @@ public class InlineByteBuddyMockMaker
     }
 
     @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+    public void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings) {
         inlineDelegateByteBuddyMockMaker.resetMock(mock, newHandler, settings);
     }
 
@@ -79,14 +79,14 @@ public class InlineByteBuddyMockMaker
 
     @Override
     public <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
+        Class<T> type, MockCreationOptions<T> settings, MockHandler handler) {
         return inlineDelegateByteBuddyMockMaker.createStaticMock(type, settings, handler);
     }
 
     @Override
     public <T> ConstructionMockControl<T> createConstructionMock(
             Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
+            Function<MockedConstruction.Context, MockCreationOptions<T>> settingsFactory,
             Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
             MockedConstruction.MockInitializer<T> mockInitializer) {
         return inlineDelegateByteBuddyMockMaker.createConstructionMock(
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
index e03d11b9e..d1a42e9d6 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMaker.java
@@ -12,13 +12,13 @@ import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.base.MockitoInitializationException;
 import org.mockito.exceptions.misusing.MockitoConfigurationException;
 import org.mockito.internal.SuppressSignatureCheck;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.creation.instance.ConstructorInstantiator;
 import org.mockito.internal.util.Platform;
 import org.mockito.internal.util.concurrent.DetachedThreadLocal;
 import org.mockito.internal.util.concurrent.WeakConcurrentMap;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.InlineMockMaker;
 import org.mockito.plugins.MemberAccessor;
 
@@ -348,13 +348,13 @@ class InlineDelegateByteBuddyMockMaker
     }
 
     @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+    public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
         return doCreateMock(settings, handler, false);
     }
 
     @Override
     public <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T object) {
+        MockCreationOptions<T> settings, MockHandler handler, T object) {
         if (object == null) {
             throw new MockitoConfigurationException("Spy instance must not be null");
         }
@@ -367,7 +367,7 @@ class InlineDelegateByteBuddyMockMaker
     }
 
     private <T> T doCreateMock(
-            MockCreationSettings<T> settings,
+            MockCreationOptions<T> settings,
             MockHandler handler,
             boolean nullOnNonInlineConstruction) {
         Class<? extends T> type = createMockType(settings);
@@ -390,7 +390,7 @@ class InlineDelegateByteBuddyMockMaker
                         return null;
                     }
                     Instantiator instantiator =
-                            Plugins.getInstantiatorProvider().getInstantiator(settings);
+                            PluginRegistry.getInstantiatorProvider().getInstantiator(settings);
                     instance = instantiator.newInstance(type);
                 }
             }
@@ -409,7 +409,7 @@ class InlineDelegateByteBuddyMockMaker
     }
 
     @Override
-    public <T> Class<? extends T> createMockType(MockCreationSettings<T> settings) {
+    public <T> Class<? extends T> createMockType(MockCreationOptions<T> settings) {
         try {
             return bytecodeGenerator.mockClass(
                     MockFeatures.withMockFeatures(
@@ -424,7 +424,7 @@ class InlineDelegateByteBuddyMockMaker
     }
 
     private <T> RuntimeException prettifyFailure(
-            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
+        MockCreationOptions<T> mockFeatures, Exception generationFailed) {
         Class<T> typeToMock = mockFeatures.getTypeToMock();
         if (typeToMock.isArray()) {
             throw new MockitoException(
@@ -500,7 +500,7 @@ class InlineDelegateByteBuddyMockMaker
     }
 
     @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+    public void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings) {
         MockMethodInterceptor mockMethodInterceptor =
                 new MockMethodInterceptor(newHandler, settings);
         if (mock instanceof Class<?>) {
@@ -574,7 +574,7 @@ class InlineDelegateByteBuddyMockMaker
 
     @Override
     public <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
+        Class<T> type, MockCreationOptions<T> settings, MockHandler handler) {
         if (type == ConcurrentHashMap.class) {
             throw new MockitoException(
                     "It is not possible to mock static methods of ConcurrentHashMap "
@@ -604,7 +604,7 @@ class InlineDelegateByteBuddyMockMaker
     @Override
     public <T> ConstructionMockControl<T> createConstructionMock(
             Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
+            Function<MockedConstruction.Context, MockCreationOptions<T>> settingsFactory,
             Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
             MockedConstruction.MockInitializer<T> mockInitializer) {
         if (type == Object.class) {
@@ -651,7 +651,7 @@ class InlineDelegateByteBuddyMockMaker
         for (Class<?> type : types) {
             arguments[index++] = makeStandardArgument(type);
         }
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor accessor = PluginRegistry.getMemberAccessor();
         try {
             return (T)
                     accessor.newInstance(
@@ -698,14 +698,14 @@ class InlineDelegateByteBuddyMockMaker
 
         private final Map<Class<?>, MockMethodInterceptor> interceptors;
 
-        private final MockCreationSettings<T> settings;
+        private final MockCreationOptions<T> settings;
 
         private final MockHandler handler;
 
         private InlineStaticMockControl(
                 Class<T> type,
                 Map<Class<?>, MockMethodInterceptor> interceptors,
-                MockCreationSettings<T> settings,
+                MockCreationOptions<T> settings,
                 MockHandler handler) {
             this.type = type;
             this.interceptors = interceptors;
@@ -752,7 +752,7 @@ class InlineDelegateByteBuddyMockMaker
 
         private final Class<T> type;
 
-        private final Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory;
+        private final Function<MockedConstruction.Context, MockCreationOptions<T>> settingsFactory;
         private final Function<MockedConstruction.Context, MockHandler<T>> handlerFactory;
 
         private final MockedConstruction.MockInitializer<T> mockInitializer;
@@ -764,7 +764,7 @@ class InlineDelegateByteBuddyMockMaker
 
         private InlineConstructionMockControl(
                 Class<T> type,
-                Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
+                Function<MockedConstruction.Context, MockCreationOptions<T>> settingsFactory,
                 Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
                 MockedConstruction.MockInitializer<T> mockInitializer,
                 Map<Class<?>, BiConsumer<Object, MockedConstruction.Context>> interceptors) {
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodAdvice.java b/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodAdvice.java
index 245917671..4ce2f9de2 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodAdvice.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodAdvice.java
@@ -49,7 +49,7 @@ import net.bytebuddy.pool.TypePool;
 import net.bytebuddy.utility.OpenedClassReader;
 
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.creation.bytebuddy.inject.MockMethodDispatcher;
 import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.exceptions.stacktrace.ConditionalStackTraceFilter;
@@ -309,7 +309,7 @@ public class MockMethodAdvice extends MockMethodDispatcher {
 
     private static Object tryInvoke(Method origin, Object instance, Object[] arguments)
             throws Throwable {
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor accessor = PluginRegistry.getMemberAccessor();
         try {
             return accessor.invoke(origin, instance, arguments);
         } catch (InvocationTargetException exception) {
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodInterceptor.java b/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodInterceptor.java
index 406dea39a..1f8e2640f 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodInterceptor.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/MockMethodInterceptor.java
@@ -26,7 +26,7 @@ import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.invocation.RealMethod;
 import org.mockito.invocation.Location;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 public class MockMethodInterceptor implements Serializable {
 
@@ -34,13 +34,13 @@ public class MockMethodInterceptor implements Serializable {
 
     final MockHandler handler;
 
-    private final MockCreationSettings mockCreationSettings;
+    private final MockCreationOptions mockCreationSettings;
 
     private final ByteBuddyCrossClassLoaderSerializationSupport serializationSupport;
 
     private transient ThreadLocal<Object> weakReferenceHatch = new ThreadLocal<>();
 
-    public MockMethodInterceptor(MockHandler handler, MockCreationSettings mockCreationSettings) {
+    public MockMethodInterceptor(MockHandler handler, MockCreationOptions mockCreationSettings) {
         this.handler = handler;
         this.mockCreationSettings = mockCreationSettings;
         serializationSupport = new ByteBuddyCrossClassLoaderSerializationSupport();
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMaker.java b/src/main/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMaker.java
index 6bb74322b..61ea62997 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMaker.java
@@ -10,10 +10,10 @@ import java.lang.reflect.Modifier;
 
 import org.mockito.creation.instance.Instantiator;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.util.Platform;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * Subclass based mock maker.
@@ -39,10 +39,10 @@ public class SubclassByteBuddyMockMaker implements ClassCreatingMockMaker {
     }
 
     @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+    public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
         Class<? extends T> mockedProxyType = createMockType(settings);
 
-        Instantiator instantiator = Plugins.getInstantiatorProvider().getInstantiator(settings);
+        Instantiator instantiator = PluginRegistry.getInstantiatorProvider().getInstantiator(settings);
         T mockInstance = null;
         try {
             mockInstance = instantiator.newInstance(mockedProxyType);
@@ -72,7 +72,7 @@ public class SubclassByteBuddyMockMaker implements ClassCreatingMockMaker {
     }
 
     @Override
-    public <T> Class<? extends T> createMockType(MockCreationSettings<T> settings) {
+    public <T> Class<? extends T> createMockType(MockCreationOptions<T> settings) {
         try {
             return cachingMockBytecodeGenerator.mockClass(
                     MockFeatures.withMockFeatures(
@@ -87,7 +87,7 @@ public class SubclassByteBuddyMockMaker implements ClassCreatingMockMaker {
     }
 
     private static <T> T ensureMockIsAssignableToMockedType(
-            MockCreationSettings<T> settings, T mock) {
+        MockCreationOptions<T> settings, T mock) {
         // Force explicit cast to mocked type here, instead of
         // relying on the JVM to implicitly cast on the client call site.
         // This allows us to catch earlier the ClassCastException earlier
@@ -96,7 +96,7 @@ public class SubclassByteBuddyMockMaker implements ClassCreatingMockMaker {
     }
 
     private <T> RuntimeException prettifyFailure(
-            MockCreationSettings<T> mockFeatures, Exception generationFailed) {
+        MockCreationOptions<T> mockFeatures, Exception generationFailed) {
         if (mockFeatures.getTypeToMock().isArray()) {
             throw new MockitoException(
                     join("Mockito cannot mock arrays: " + mockFeatures.getTypeToMock() + ".", ""),
@@ -152,7 +152,7 @@ public class SubclassByteBuddyMockMaker implements ClassCreatingMockMaker {
     }
 
     @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+    public void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings) {
         ((MockAccess) mock).setMockitoInterceptor(new MockMethodInterceptor(newHandler, settings));
     }
 
diff --git a/src/main/java/org/mockito/internal/creation/instance/ConstructorInstantiator.java b/src/main/java/org/mockito/internal/creation/instance/ConstructorInstantiator.java
index 30094c58b..3ee606b13 100644
--- a/src/main/java/org/mockito/internal/creation/instance/ConstructorInstantiator.java
+++ b/src/main/java/org/mockito/internal/creation/instance/ConstructorInstantiator.java
@@ -14,7 +14,7 @@ import java.util.List;
 
 import org.mockito.creation.instance.InstantiationException;
 import org.mockito.creation.instance.Instantiator;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.util.Primitives;
 import org.mockito.plugins.MemberAccessor;
 
@@ -67,7 +67,7 @@ public class ConstructorInstantiator implements Instantiator {
             throws java.lang.InstantiationException,
                     IllegalAccessException,
                     InvocationTargetException {
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor accessor = PluginRegistry.getMemberAccessor();
         return (T) accessor.newInstance(constructor, params);
     }
 
diff --git a/src/main/java/org/mockito/internal/creation/instance/DefaultInstantiatorProvider.java b/src/main/java/org/mockito/internal/creation/instance/DefaultInstantiatorProvider.java
index af071bfb3..58abad462 100644
--- a/src/main/java/org/mockito/internal/creation/instance/DefaultInstantiatorProvider.java
+++ b/src/main/java/org/mockito/internal/creation/instance/DefaultInstantiatorProvider.java
@@ -5,7 +5,7 @@
 package org.mockito.internal.creation.instance;
 
 import org.mockito.creation.instance.Instantiator;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.InstantiatorProvider2;
 
 public class DefaultInstantiatorProvider implements InstantiatorProvider2 {
@@ -13,7 +13,7 @@ public class DefaultInstantiatorProvider implements InstantiatorProvider2 {
     private static final Instantiator INSTANCE = new ObjenesisInstantiator();
 
     @Override
-    public Instantiator getInstantiator(MockCreationSettings<?> settings) {
+    public Instantiator getInstantiator(MockCreationOptions<?> settings) {
         if (settings != null && settings.getConstructorArgs() != null) {
             return new ConstructorInstantiator(
                     settings.getOuterClassInstance() != null, settings.getConstructorArgs());
diff --git a/src/main/java/org/mockito/internal/creation/proxy/ProxyMockMaker.java b/src/main/java/org/mockito/internal/creation/proxy/ProxyMockMaker.java
index 88e688611..30b824dc3 100644
--- a/src/main/java/org/mockito/internal/creation/proxy/ProxyMockMaker.java
+++ b/src/main/java/org/mockito/internal/creation/proxy/ProxyMockMaker.java
@@ -9,7 +9,7 @@ import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.invocation.RealMethod;
 import org.mockito.internal.util.Platform;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.MockMaker;
 
 import java.lang.reflect.InvocationHandler;
@@ -33,7 +33,7 @@ public class ProxyMockMaker implements MockMaker {
 
     @Override
     @SuppressWarnings("unchecked")
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+    public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
         boolean object = settings.getTypeToMock() == Object.class;
         Class<?>[] ifaces = new Class<?>[settings.getExtraInterfaces().size() + (object ? 0 : 1)];
         int index = 0;
@@ -89,7 +89,7 @@ public class ProxyMockMaker implements MockMaker {
     }
 
     @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+    public void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings) {
         ((MockInvocationHandler) Proxy.getInvocationHandler(mock)).handler.set(newHandler);
     }
 
@@ -112,9 +112,9 @@ public class ProxyMockMaker implements MockMaker {
 
         private final AtomicReference<MockHandler<?>> handler;
 
-        private final MockCreationSettings<?> settings;
+        private final MockCreationOptions<?> settings;
 
-        private MockInvocationHandler(MockHandler<?> handler, MockCreationSettings<?> settings) {
+        private MockInvocationHandler(MockHandler<?> handler, MockCreationOptions<?> settings) {
             this.handler = new AtomicReference<>(handler);
             this.settings = settings;
         }
diff --git a/src/main/java/org/mockito/internal/creation/settings/CreationSettings.java b/src/main/java/org/mockito/internal/creation/settings/MockCreationSettings.java
similarity index 62%
rename from src/main/java/org/mockito/internal/creation/settings/CreationSettings.java
rename to src/main/java/org/mockito/internal/creation/settings/MockCreationSettings.java
index 51544fb9e..d15afbbe7 100644
--- a/src/main/java/org/mockito/internal/creation/settings/CreationSettings.java
+++ b/src/main/java/org/mockito/internal/creation/settings/MockCreationSettings.java
@@ -16,14 +16,14 @@ import java.util.concurrent.CopyOnWriteArrayList;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.listeners.StubbingLookupListener;
 import org.mockito.listeners.VerificationStartedListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.mock.MockName;
 import org.mockito.mock.SerializableMode;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Answer;
 
-public class CreationSettings<T> implements MockCreationSettings<T>, Serializable {
-    private static final long serialVersionUID = -6789800638070123629L;
+public class MockCreationSettings<T> implements MockCreationOptions<T>, Serializable {
+    private static final long SERIALIZATION_ID = -6789800638070123629L;
 
     protected Class<T> typeToMock;
     protected transient Type genericTypeToMock;
@@ -44,35 +44,35 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
     protected List<VerificationStartedListener> verificationStartedListeners = new LinkedList<>();
     protected boolean stubOnly;
     protected boolean stripAnnotations;
-    private boolean useConstructor;
-    private Object outerClassInstance;
-    private Object[] constructorArgs;
+    private boolean preferConstructor;
+    private Object enclosingInstance;
+    private Object[] constructorArguments;
     protected Strictness strictness = null;
     protected String mockMaker;
 
-    public CreationSettings() {}
+    public MockCreationSettings() {}
 
     @SuppressWarnings("unchecked")
-    public CreationSettings(CreationSettings copy) {
+    public MockCreationSettings(MockCreationSettings originalSettings) {
         // TODO can we have a reflection test here? We had a couple of bugs here in the past.
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
+        this.typeToMock = originalSettings.typeToMock;
+        this.genericTypeToMock = originalSettings.genericTypeToMock;
+        this.extraInterfaces = originalSettings.extraInterfaces;
+        this.name = originalSettings.name;
+        this.spiedInstance = originalSettings.spiedInstance;
+        this.defaultAnswer = originalSettings.defaultAnswer;
+        this.mockName = originalSettings.mockName;
+        this.serializableMode = originalSettings.serializableMode;
+        this.invocationListeners = originalSettings.invocationListeners;
+        this.stubbingLookupListeners = originalSettings.stubbingLookupListeners;
+        this.verificationStartedListeners = originalSettings.verificationStartedListeners;
+        this.stubOnly = originalSettings.stubOnly;
+        this.preferConstructor = originalSettings.isUsingConstructor();
+        this.enclosingInstance = originalSettings.getOuterClassInstance();
+        this.constructorArguments = originalSettings.getConstructorArgs();
+        this.strictness = originalSettings.strictness;
+        this.stripAnnotations = originalSettings.stripAnnotations;
+        this.mockMaker = originalSettings.mockMaker;
     }
 
     @Override
@@ -80,13 +80,13 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
         return typeToMock;
     }
 
-    public CreationSettings<T> setTypeToMock(Class<T> typeToMock) {
-        this.typeToMock = typeToMock;
+    public MockCreationSettings<T> setTypeToMock(Class<T> mockType) {
+        this.typeToMock = mockType;
         return this;
     }
 
-    public CreationSettings<T> setGenericTypeToMock(Type genericTypeToMock) {
-        this.genericTypeToMock = genericTypeToMock;
+    public MockCreationSettings<T> setGenericTypeToMock(Type mockGenericType) {
+        this.genericTypeToMock = mockGenericType;
         return this;
     }
 
@@ -95,8 +95,8 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
         return extraInterfaces;
     }
 
-    public CreationSettings<T> setExtraInterfaces(Set<Class<?>> extraInterfaces) {
-        this.extraInterfaces = extraInterfaces;
+    public MockCreationSettings<T> setExtraInterfaces(Set<Class<?>> additionalInterfaces) {
+        this.extraInterfaces = additionalInterfaces;
         return this;
     }
 
@@ -119,8 +119,8 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
         return mockName;
     }
 
-    public CreationSettings<T> setMockName(MockName mockName) {
-        this.mockName = mockName;
+    public MockCreationSettings<T> setMockName(MockName mockIdentifier) {
+        this.mockName = mockIdentifier;
         return this;
     }
 
@@ -129,8 +129,8 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
         return serializableMode != SerializableMode.NONE;
     }
 
-    public CreationSettings<T> setSerializableMode(SerializableMode serializableMode) {
-        this.serializableMode = serializableMode;
+    public MockCreationSettings<T> setSerializableMode(SerializableMode serializationMode) {
+        this.serializableMode = serializationMode;
         return this;
     }
 
@@ -156,7 +156,7 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
 
     @Override
     public boolean isUsingConstructor() {
-        return useConstructor;
+        return preferConstructor;
     }
 
     @Override
@@ -166,12 +166,12 @@ public class CreationSettings<T> implements MockCreationSettings<T>, Serializabl
 
     @Override
     public Object[] getConstructorArgs() {
-        return constructorArgs;
+        return constructorArguments;
     }
 
     @Override
     public Object getOuterClassInstance() {
-        return outerClassInstance;
+        return enclosingInstance;
     }
 
     @Override
diff --git a/src/main/java/org/mockito/internal/debugging/LocationImpl.java b/src/main/java/org/mockito/internal/debugging/LocationImpl.java
index ea72eeb7f..207e2b846 100644
--- a/src/main/java/org/mockito/internal/debugging/LocationImpl.java
+++ b/src/main/java/org/mockito/internal/debugging/LocationImpl.java
@@ -7,7 +7,7 @@ package org.mockito.internal.debugging;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.stacktrace.StackTraceCleaner;
 import org.mockito.exceptions.stacktrace.StackTraceCleaner.StackFrameMetadata;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.exceptions.stacktrace.DefaultStackTraceCleaner;
 import org.mockito.invocation.Location;
 
@@ -42,7 +42,7 @@ class LocationImpl implements Location, Serializable {
     private static final String PREFIX = "-> at ";
 
     private static final StackTraceCleaner CLEANER =
-            Plugins.getStackTraceCleanerProvider()
+            PluginRegistry.getStackTraceCleanerProvider()
                     .getStackTraceCleaner(new DefaultStackTraceCleaner());
 
     /**
diff --git a/src/main/java/org/mockito/internal/exceptions/stacktrace/StackTraceFilter.java b/src/main/java/org/mockito/internal/exceptions/stacktrace/StackTraceFilter.java
index ad0ede213..e1e919fca 100644
--- a/src/main/java/org/mockito/internal/exceptions/stacktrace/StackTraceFilter.java
+++ b/src/main/java/org/mockito/internal/exceptions/stacktrace/StackTraceFilter.java
@@ -10,14 +10,14 @@ import java.util.ArrayList;
 import java.util.List;
 
 import org.mockito.exceptions.stacktrace.StackTraceCleaner;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 
 public class StackTraceFilter implements Serializable {
 
     static final long serialVersionUID = -5499819791513105700L;
 
     private static final StackTraceCleaner CLEANER =
-            Plugins.getStackTraceCleanerProvider()
+            PluginRegistry.getStackTraceCleanerProvider()
                     .getStackTraceCleaner(new DefaultStackTraceCleaner());
 
     private static Object JAVA_LANG_ACCESS;
diff --git a/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java b/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
index f4a988231..e8531b7b4 100644
--- a/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
+++ b/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
@@ -7,7 +7,7 @@ package org.mockito.internal.framework;
 import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
 
 import org.mockito.MockitoFramework;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.invocation.DefaultInvocationFactory;
 import org.mockito.internal.util.Checks;
 import org.mockito.invocation.InvocationFactory;
@@ -34,7 +34,7 @@ public class DefaultMockitoFramework implements MockitoFramework {
 
     @Override
     public MockitoPlugins getPlugins() {
-        return Plugins.getPlugins();
+        return PluginRegistry.getPlugins();
     }
 
     @Override
@@ -43,7 +43,7 @@ public class DefaultMockitoFramework implements MockitoFramework {
     }
 
     private InlineMockMaker getInlineMockMaker() {
-        MockMaker mockMaker = Plugins.getMockMaker();
+        MockMaker mockMaker = PluginRegistry.getMockMaker();
         return (mockMaker instanceof InlineMockMaker) ? (InlineMockMaker) mockMaker : null;
     }
 
diff --git a/src/main/java/org/mockito/internal/handler/InvocationNotifierHandler.java b/src/main/java/org/mockito/internal/handler/InvocationNotifierHandler.java
index b1c84dfd9..71d0cfebc 100644
--- a/src/main/java/org/mockito/internal/handler/InvocationNotifierHandler.java
+++ b/src/main/java/org/mockito/internal/handler/InvocationNotifierHandler.java
@@ -12,7 +12,7 @@ import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MockHandler;
 import org.mockito.listeners.InvocationListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * Handler, that call all listeners wanted for this mock, before delegating it
@@ -23,7 +23,7 @@ class InvocationNotifierHandler<T> implements MockHandler<T> {
     private final List<InvocationListener> invocationListeners;
     private final MockHandler<T> mockHandler;
 
-    public InvocationNotifierHandler(MockHandler<T> mockHandler, MockCreationSettings<T> settings) {
+    public InvocationNotifierHandler(MockHandler<T> mockHandler, MockCreationOptions<T> settings) {
         this.mockHandler = mockHandler;
         this.invocationListeners = settings.getInvocationListeners();
     }
@@ -63,7 +63,7 @@ class InvocationNotifierHandler<T> implements MockHandler<T> {
     }
 
     @Override
-    public MockCreationSettings<T> getMockSettings() {
+    public MockCreationOptions<T> getMockSettings() {
         return mockHandler.getMockSettings();
     }
 
diff --git a/src/main/java/org/mockito/internal/handler/MockHandlerFactory.java b/src/main/java/org/mockito/internal/handler/MockHandlerFactory.java
index c735cd43c..afb8e03d8 100644
--- a/src/main/java/org/mockito/internal/handler/MockHandlerFactory.java
+++ b/src/main/java/org/mockito/internal/handler/MockHandlerFactory.java
@@ -5,12 +5,12 @@
 package org.mockito.internal.handler;
 
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /** by Szczepan Faber, created at: 5/21/12 */
 public final class MockHandlerFactory {
 
-    public static <T> MockHandler<T> createMockHandler(MockCreationSettings<T> settings) {
+    public static <T> MockHandler<T> createMockHandler(MockCreationOptions<T> settings) {
         MockHandler<T> handler = new MockHandlerImpl<T>(settings);
         MockHandler<T> nullResultGuardian = new NullResultGuardian<T>(handler);
         return new InvocationNotifierHandler<T>(nullResultGuardian, settings);
diff --git a/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java b/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
index e58659a16..3b2bb860e 100644
--- a/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
+++ b/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
@@ -7,7 +7,7 @@ package org.mockito.internal.handler;
 import static org.mockito.internal.listeners.StubbingLookupNotifier.notifyStubbedAnswerLookup;
 import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
 
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.internal.invocation.InvocationMatcher;
 import org.mockito.internal.invocation.MatchersBinder;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
@@ -20,7 +20,7 @@ import org.mockito.internal.verification.VerificationDataImpl;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.verification.VerificationMode;
 
 /**
@@ -36,9 +36,9 @@ public class MockHandlerImpl<T> implements MockHandler<T> {
 
     MatchersBinder matchersBinder = new MatchersBinder();
 
-    private final MockCreationSettings<T> mockSettings;
+    private final MockCreationOptions<T> mockSettings;
 
-    public MockHandlerImpl(MockCreationSettings<T> mockSettings) {
+    public MockHandlerImpl(MockCreationOptions<T> mockSettings) {
         this.mockSettings = mockSettings;
 
         this.matchersBinder = new MatchersBinder();
@@ -94,7 +94,7 @@ public class MockHandlerImpl<T> implements MockHandler<T> {
                 invocation,
                 stubbing,
                 invocationContainer.getStubbingsAscending(),
-                (CreationSettings) mockSettings);
+                (MockCreationSettings) mockSettings);
 
         if (stubbing != null) {
             stubbing.captureArgumentsFrom(invocation);
@@ -130,7 +130,7 @@ public class MockHandlerImpl<T> implements MockHandler<T> {
     }
 
     @Override
-    public MockCreationSettings<T> getMockSettings() {
+    public MockCreationOptions<T> getMockSettings() {
         return mockSettings;
     }
 
diff --git a/src/main/java/org/mockito/internal/handler/NullResultGuardian.java b/src/main/java/org/mockito/internal/handler/NullResultGuardian.java
index 65de62e06..5c1a9ccc0 100644
--- a/src/main/java/org/mockito/internal/handler/NullResultGuardian.java
+++ b/src/main/java/org/mockito/internal/handler/NullResultGuardian.java
@@ -9,7 +9,7 @@ import static org.mockito.internal.util.Primitives.defaultValue;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * Protects the results from delegate MockHandler. Makes sure the results are valid.
@@ -36,7 +36,7 @@ class NullResultGuardian<T> implements MockHandler<T> {
     }
 
     @Override
-    public MockCreationSettings<T> getMockSettings() {
+    public MockCreationOptions<T> getMockSettings() {
         return delegate.getMockSettings();
     }
 
diff --git a/src/main/java/org/mockito/internal/invocation/DefaultInvocationFactory.java b/src/main/java/org/mockito/internal/invocation/DefaultInvocationFactory.java
index 4921f4006..71d7c868a 100644
--- a/src/main/java/org/mockito/internal/invocation/DefaultInvocationFactory.java
+++ b/src/main/java/org/mockito/internal/invocation/DefaultInvocationFactory.java
@@ -14,13 +14,13 @@ import org.mockito.internal.progress.SequenceNumber;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationFactory;
 import org.mockito.invocation.Location;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 public class DefaultInvocationFactory implements InvocationFactory {
 
     public Invocation createInvocation(
             Object target,
-            MockCreationSettings settings,
+            MockCreationOptions settings,
             Method method,
             final Callable realMethod,
             Object... args) {
@@ -31,7 +31,7 @@ public class DefaultInvocationFactory implements InvocationFactory {
     @Override
     public Invocation createInvocation(
             Object target,
-            MockCreationSettings settings,
+            MockCreationOptions settings,
             Method method,
             RealMethodBehavior realMethod,
             Object... args) {
@@ -41,7 +41,7 @@ public class DefaultInvocationFactory implements InvocationFactory {
 
     private Invocation createInvocation(
             Object target,
-            MockCreationSettings settings,
+            MockCreationOptions settings,
             Method method,
             RealMethod superMethod,
             Object[] args) {
@@ -53,7 +53,7 @@ public class DefaultInvocationFactory implements InvocationFactory {
             Method invokedMethod,
             Object[] arguments,
             RealMethod realMethod,
-            MockCreationSettings settings,
+            MockCreationOptions settings,
             Location location) {
         return new InterceptedInvocation(
                 new MockWeakReference<Object>(mock),
@@ -69,12 +69,12 @@ public class DefaultInvocationFactory implements InvocationFactory {
             Method invokedMethod,
             Object[] arguments,
             RealMethod realMethod,
-            MockCreationSettings settings) {
+            MockCreationOptions settings) {
         return createInvocation(
                 mock, invokedMethod, arguments, realMethod, settings, LocationFactory.create());
     }
 
-    private static MockitoMethod createMockitoMethod(Method method, MockCreationSettings settings) {
+    private static MockitoMethod createMockitoMethod(Method method, MockCreationOptions settings) {
         if (settings.isSerializable()) {
             return new SerializableMethod(method);
         } else {
diff --git a/src/main/java/org/mockito/internal/junit/MismatchReportingTestListener.java b/src/main/java/org/mockito/internal/junit/MismatchReportingTestListener.java
index ec877b508..e6dedca59 100644
--- a/src/main/java/org/mockito/internal/junit/MismatchReportingTestListener.java
+++ b/src/main/java/org/mockito/internal/junit/MismatchReportingTestListener.java
@@ -8,7 +8,7 @@ import java.util.Collection;
 import java.util.LinkedList;
 import java.util.List;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.MockitoLogger;
 
 /**
@@ -42,7 +42,7 @@ public class MismatchReportingTestListener implements MockitoTestListener {
     }
 
     @Override
-    public void onMockCreated(Object mock, MockCreationSettings settings) {
+    public void onMockCreated(Object mock, MockCreationOptions settings) {
         this.mocks.add(mock);
     }
 }
diff --git a/src/main/java/org/mockito/internal/junit/NoOpTestListener.java b/src/main/java/org/mockito/internal/junit/NoOpTestListener.java
index 77c7d4ecd..29b2c6418 100644
--- a/src/main/java/org/mockito/internal/junit/NoOpTestListener.java
+++ b/src/main/java/org/mockito/internal/junit/NoOpTestListener.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.junit;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 public class NoOpTestListener implements MockitoTestListener {
 
@@ -12,5 +12,5 @@ public class NoOpTestListener implements MockitoTestListener {
     public void testFinished(TestFinishedEvent event) {}
 
     @Override
-    public void onMockCreated(Object mock, MockCreationSettings settings) {}
+    public void onMockCreated(Object mock, MockCreationOptions settings) {}
 }
diff --git a/src/main/java/org/mockito/internal/junit/StrictStubsRunnerTestListener.java b/src/main/java/org/mockito/internal/junit/StrictStubsRunnerTestListener.java
index 8d6cc6c73..4d0c6f16f 100644
--- a/src/main/java/org/mockito/internal/junit/StrictStubsRunnerTestListener.java
+++ b/src/main/java/org/mockito/internal/junit/StrictStubsRunnerTestListener.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.junit;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.quality.Strictness;
 
 /**
@@ -19,7 +19,7 @@ public class StrictStubsRunnerTestListener implements MockitoTestListener {
     public void testFinished(TestFinishedEvent event) {}
 
     @Override
-    public void onMockCreated(Object mock, MockCreationSettings settings) {
+    public void onMockCreated(Object mock, MockCreationOptions settings) {
         // It is not ideal that we modify the state of MockCreationSettings object
         // MockCreationSettings is intended to be an immutable view of the creation settings
         // However, we our previous listeners work this way and it hasn't backfired.
diff --git a/src/main/java/org/mockito/internal/junit/UniversalTestListener.java b/src/main/java/org/mockito/internal/junit/UniversalTestListener.java
index 72e3c0912..3f54ebf5c 100644
--- a/src/main/java/org/mockito/internal/junit/UniversalTestListener.java
+++ b/src/main/java/org/mockito/internal/junit/UniversalTestListener.java
@@ -6,9 +6,9 @@ package org.mockito.internal.junit;
 
 import java.util.Collection;
 import java.util.IdentityHashMap;
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.internal.listeners.AutoCleanableListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.MockitoLogger;
 import org.mockito.quality.Strictness;
 
@@ -22,7 +22,7 @@ public class UniversalTestListener implements MockitoTestListener, AutoCleanable
     private Strictness currentStrictness;
     private final MockitoLogger logger;
 
-    private IdentityHashMap mocks = new IdentityHashMap<Object, MockCreationSettings>();
+    private IdentityHashMap mocks = new IdentityHashMap<Object, MockCreationOptions>();
     private final DefaultStubbingLookupListener stubbingLookupListener;
     private boolean listenerDirty;
 
@@ -87,7 +87,7 @@ public class UniversalTestListener implements MockitoTestListener, AutoCleanable
     }
 
     @Override
-    public void onMockCreated(Object mock, MockCreationSettings settings) {
+    public void onMockCreated(Object mock, MockCreationOptions settings) {
         this.mocks.put(mock, settings);
 
         // It is not ideal that we modify the state of MockCreationSettings object
@@ -95,7 +95,7 @@ public class UniversalTestListener implements MockitoTestListener, AutoCleanable
         // In future, we should start passing MockSettings object to the creation listener
         // TODO #793 - when completed, we should be able to get rid of the CreationSettings casting
         // below
-        ((CreationSettings) settings).getStubbingLookupListeners().add(stubbingLookupListener);
+        ((MockCreationSettings) settings).getStubbingLookupListeners().add(stubbingLookupListener);
     }
 
     public void setStrictness(Strictness strictness) {
diff --git a/src/main/java/org/mockito/internal/junit/UnnecessaryStubbingsReporter.java b/src/main/java/org/mockito/internal/junit/UnnecessaryStubbingsReporter.java
index 2ba1fb962..dbe6e1a37 100644
--- a/src/main/java/org/mockito/internal/junit/UnnecessaryStubbingsReporter.java
+++ b/src/main/java/org/mockito/internal/junit/UnnecessaryStubbingsReporter.java
@@ -14,7 +14,7 @@ import org.junit.runner.notification.RunNotifier;
 import org.mockito.internal.exceptions.Reporter;
 import org.mockito.invocation.Invocation;
 import org.mockito.listeners.MockCreationListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * Reports unnecessary stubbings
@@ -40,7 +40,7 @@ public class UnnecessaryStubbingsReporter implements MockCreationListener {
     }
 
     @Override
-    public void onMockCreated(Object mock, MockCreationSettings settings) {
+    public void onMockCreated(Object mock, MockCreationOptions settings) {
         mocks.add(mock);
     }
 }
diff --git a/src/main/java/org/mockito/internal/listeners/StubbingLookupNotifier.java b/src/main/java/org/mockito/internal/listeners/StubbingLookupNotifier.java
index 533162890..6a8c7aaee 100644
--- a/src/main/java/org/mockito/internal/listeners/StubbingLookupNotifier.java
+++ b/src/main/java/org/mockito/internal/listeners/StubbingLookupNotifier.java
@@ -7,11 +7,11 @@ package org.mockito.internal.listeners;
 import java.util.Collection;
 import java.util.List;
 
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.invocation.Invocation;
 import org.mockito.listeners.StubbingLookupEvent;
 import org.mockito.listeners.StubbingLookupListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.Stubbing;
 
 public final class StubbingLookupNotifier {
@@ -20,7 +20,7 @@ public final class StubbingLookupNotifier {
             Invocation invocation,
             Stubbing stubbingFound,
             Collection<Stubbing> allStubbings,
-            CreationSettings creationSettings) {
+            MockCreationSettings creationSettings) {
         List<StubbingLookupListener> listeners = creationSettings.getStubbingLookupListeners();
         if (listeners.isEmpty()) {
             return;
@@ -36,13 +36,13 @@ public final class StubbingLookupNotifier {
         private final Invocation invocation;
         private final Stubbing stubbing;
         private final Collection<Stubbing> allStubbings;
-        private final MockCreationSettings mockSettings;
+        private final MockCreationOptions mockSettings;
 
         public Event(
                 Invocation invocation,
                 Stubbing stubbing,
                 Collection<Stubbing> allStubbings,
-                MockCreationSettings mockSettings) {
+                MockCreationOptions mockSettings) {
             this.invocation = invocation;
             this.stubbing = stubbing;
             this.allStubbings = allStubbings;
@@ -65,7 +65,7 @@ public final class StubbingLookupNotifier {
         }
 
         @Override
-        public MockCreationSettings getMockSettings() {
+        public MockCreationOptions getMockSettings() {
             return mockSettings;
         }
     }
diff --git a/src/main/java/org/mockito/internal/listeners/VerificationStartedNotifier.java b/src/main/java/org/mockito/internal/listeners/VerificationStartedNotifier.java
index 9a5a89060..68f3fb621 100644
--- a/src/main/java/org/mockito/internal/listeners/VerificationStartedNotifier.java
+++ b/src/main/java/org/mockito/internal/listeners/VerificationStartedNotifier.java
@@ -13,7 +13,7 @@ import org.mockito.internal.exceptions.Reporter;
 import org.mockito.internal.matchers.text.ValuePrinter;
 import org.mockito.listeners.VerificationStartedEvent;
 import org.mockito.listeners.VerificationStartedListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 public final class VerificationStartedNotifier {
 
@@ -53,7 +53,7 @@ public final class VerificationStartedNotifier {
                                 + ValuePrinter.print(mock)
                                 + ".\n ");
             }
-            MockCreationSettings originalMockSettings =
+            MockCreationOptions originalMockSettings =
                     this.originalMockingDetails.getMockCreationSettings();
             assertCompatibleTypes(mock, originalMockSettings);
             this.mock = mock;
@@ -65,7 +65,7 @@ public final class VerificationStartedNotifier {
         }
     }
 
-    static void assertCompatibleTypes(Object mock, MockCreationSettings originalSettings) {
+    static void assertCompatibleTypes(Object mock, MockCreationOptions originalSettings) {
         Class originalType = originalSettings.getTypeToMock();
         if (!originalType.isInstance(mock)) {
             throw Reporter.methodDoesNotAcceptParameter(
diff --git a/src/main/java/org/mockito/internal/matchers/apachecommons/EqualsBuilder.java b/src/main/java/org/mockito/internal/matchers/apachecommons/EqualsBuilder.java
index eaa151685..b1e6415a6 100644
--- a/src/main/java/org/mockito/internal/matchers/apachecommons/EqualsBuilder.java
+++ b/src/main/java/org/mockito/internal/matchers/apachecommons/EqualsBuilder.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.matchers.apachecommons;
 
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.MemberAccessor;
 
 import java.lang.reflect.Field;
@@ -292,7 +292,7 @@ class EqualsBuilder {
                 excludeFields != null
                         ? Arrays.asList(excludeFields)
                         : Collections.<String>emptyList();
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor accessor = PluginRegistry.getMemberAccessor();
         for (int i = 0; i < fields.length && builder.isEquals; i++) {
             Field f = fields[i];
             if (!excludedFieldList.contains(f.getName())
diff --git a/src/main/java/org/mockito/internal/progress/MockingProgress.java b/src/main/java/org/mockito/internal/progress/MockingProgress.java
index abdf68d83..fe4529613 100644
--- a/src/main/java/org/mockito/internal/progress/MockingProgress.java
+++ b/src/main/java/org/mockito/internal/progress/MockingProgress.java
@@ -8,7 +8,7 @@ import java.util.Set;
 
 import org.mockito.listeners.MockitoListener;
 import org.mockito.listeners.VerificationListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.OngoingStubbing;
 import org.mockito.verification.VerificationMode;
 import org.mockito.verification.VerificationStrategy;
@@ -41,9 +41,9 @@ public interface MockingProgress {
 
     ArgumentMatcherStorage getArgumentMatcherStorage();
 
-    void mockingStarted(Object mock, MockCreationSettings settings);
+    void mockingStarted(Object mock, MockCreationOptions settings);
 
-    void mockingStarted(Class<?> mock, MockCreationSettings settings);
+    void mockingStarted(Class<?> mock, MockCreationOptions settings);
 
     void addListener(MockitoListener listener);
 
diff --git a/src/main/java/org/mockito/internal/progress/MockingProgressImpl.java b/src/main/java/org/mockito/internal/progress/MockingProgressImpl.java
index 2585d32cf..202b4d2fe 100644
--- a/src/main/java/org/mockito/internal/progress/MockingProgressImpl.java
+++ b/src/main/java/org/mockito/internal/progress/MockingProgressImpl.java
@@ -21,7 +21,7 @@ import org.mockito.invocation.Location;
 import org.mockito.listeners.MockCreationListener;
 import org.mockito.listeners.MockitoListener;
 import org.mockito.listeners.VerificationListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.OngoingStubbing;
 import org.mockito.verification.VerificationMode;
 import org.mockito.verification.VerificationStrategy;
@@ -163,7 +163,7 @@ public class MockingProgressImpl implements MockingProgress {
     }
 
     @Override
-    public void mockingStarted(Object mock, MockCreationSettings settings) {
+    public void mockingStarted(Object mock, MockCreationOptions settings) {
         for (MockitoListener listener : listeners) {
             if (listener instanceof MockCreationListener) {
                 ((MockCreationListener) listener).onMockCreated(mock, settings);
@@ -173,7 +173,7 @@ public class MockingProgressImpl implements MockingProgress {
     }
 
     @Override
-    public void mockingStarted(Class<?> mock, MockCreationSettings settings) {
+    public void mockingStarted(Class<?> mock, MockCreationOptions settings) {
         for (MockitoListener listener : listeners) {
             if (listener instanceof MockCreationListener) {
                 ((MockCreationListener) listener).onStaticMockCreated(mock, settings);
diff --git a/src/main/java/org/mockito/internal/runners/RunnerFactory.java b/src/main/java/org/mockito/internal/runners/RunnerFactory.java
index 68ef16cd1..3421f7597 100644
--- a/src/main/java/org/mockito/internal/runners/RunnerFactory.java
+++ b/src/main/java/org/mockito/internal/runners/RunnerFactory.java
@@ -9,7 +9,7 @@ import static org.mockito.internal.runners.util.TestMethodsFinder.hasTestMethods
 import java.lang.reflect.InvocationTargetException;
 
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.junit.MismatchReportingTestListener;
 import org.mockito.internal.junit.MockitoTestListener;
 import org.mockito.internal.junit.NoOpTestListener;
@@ -41,7 +41,7 @@ public class RunnerFactory {
                 klass,
                 new Supplier<MockitoTestListener>() {
                     public MockitoTestListener get() {
-                        return new MismatchReportingTestListener(Plugins.getMockitoLogger());
+                        return new MismatchReportingTestListener(PluginRegistry.getMockitoLogger());
                     }
                 });
     }
diff --git a/src/main/java/org/mockito/internal/session/DefaultMockitoSessionBuilder.java b/src/main/java/org/mockito/internal/session/DefaultMockitoSessionBuilder.java
index 6fe3dcb62..8469f478c 100644
--- a/src/main/java/org/mockito/internal/session/DefaultMockitoSessionBuilder.java
+++ b/src/main/java/org/mockito/internal/session/DefaultMockitoSessionBuilder.java
@@ -10,7 +10,7 @@ import java.util.ArrayList;
 import java.util.List;
 
 import org.mockito.MockitoSession;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.framework.DefaultMockitoSession;
 import org.mockito.plugins.MockitoLogger;
 import org.mockito.quality.Strictness;
@@ -78,7 +78,7 @@ public class DefaultMockitoSessionBuilder implements MockitoSessionBuilder {
                 this.strictness == null ? Strictness.STRICT_STUBS : this.strictness;
         MockitoLogger logger =
                 this.logger == null
-                        ? Plugins.getMockitoLogger()
+                        ? PluginRegistry.getMockitoLogger()
                         : new MockitoLoggerAdapter(this.logger);
         return new DefaultMockitoSession(
                 effectiveTestClassInstances, effectiveName, effectiveStrictness, logger);
diff --git a/src/main/java/org/mockito/internal/stubbing/DefaultLenientStubber.java b/src/main/java/org/mockito/internal/stubbing/DefaultLenientStubber.java
index 6986c20e3..a40f16243 100644
--- a/src/main/java/org/mockito/internal/stubbing/DefaultLenientStubber.java
+++ b/src/main/java/org/mockito/internal/stubbing/DefaultLenientStubber.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.stubbing;
 
-import org.mockito.internal.MockitoCore;
+import org.mockito.internal.MockitoEngine;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Answer;
 import org.mockito.stubbing.LenientStubber;
@@ -13,7 +13,7 @@ import org.mockito.stubbing.Stubber;
 
 public class DefaultLenientStubber implements LenientStubber {
 
-    private static final MockitoCore MOCKITO_CORE = new MockitoCore();
+    private static final MockitoEngine MOCKITO_CORE = new MockitoEngine();
 
     @Override
     public Stubber doThrow(Throwable... toBeThrown) {
@@ -59,12 +59,12 @@ public class DefaultLenientStubber implements LenientStubber {
     @Override
     public <T> OngoingStubbing<T> when(T methodCall) {
         OngoingStubbingImpl<T> ongoingStubbing =
-                (OngoingStubbingImpl) MOCKITO_CORE.when(methodCall);
+                (OngoingStubbingImpl) MOCKITO_CORE.beginStubbing(methodCall);
         ongoingStubbing.setStrictness(Strictness.LENIENT);
         return ongoingStubbing;
     }
 
     private static Stubber stubber() {
-        return MOCKITO_CORE.stubber(Strictness.LENIENT);
+        return MOCKITO_CORE.getStubber(Strictness.LENIENT);
     }
 }
diff --git a/src/main/java/org/mockito/internal/stubbing/InvocationContainerImpl.java b/src/main/java/org/mockito/internal/stubbing/InvocationContainerImpl.java
index 927d230e0..4ac64e961 100644
--- a/src/main/java/org/mockito/internal/stubbing/InvocationContainerImpl.java
+++ b/src/main/java/org/mockito/internal/stubbing/InvocationContainerImpl.java
@@ -19,7 +19,7 @@ import org.mockito.internal.verification.SingleRegisteredInvocation;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MatchableInvocation;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Answer;
 import org.mockito.stubbing.Stubbing;
@@ -35,7 +35,7 @@ public class InvocationContainerImpl implements InvocationContainer, Serializabl
 
     private MatchableInvocation invocationForStubbing;
 
-    public InvocationContainerImpl(MockCreationSettings<?> mockSettings) {
+    public InvocationContainerImpl(MockCreationOptions<?> mockSettings) {
         this.registeredInvocations = createRegisteredInvocations(mockSettings);
         this.mockStrictness = mockSettings.getStrictness();
         this.doAnswerStyleStubbing = new DoAnswerStyleStubbing();
@@ -159,7 +159,7 @@ public class InvocationContainerImpl implements InvocationContainer, Serializabl
     }
 
     private RegisteredInvocations createRegisteredInvocations(
-            MockCreationSettings<?> mockSettings) {
+            MockCreationOptions<?> mockSettings) {
         return mockSettings.isStubOnly()
                 ? new SingleRegisteredInvocation()
                 : new DefaultRegisteredInvocations();
diff --git a/src/main/java/org/mockito/internal/stubbing/StrictnessSelector.java b/src/main/java/org/mockito/internal/stubbing/StrictnessSelector.java
index c8e7e4440..21fbcc852 100644
--- a/src/main/java/org/mockito/internal/stubbing/StrictnessSelector.java
+++ b/src/main/java/org/mockito/internal/stubbing/StrictnessSelector.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.stubbing;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Stubbing;
 
@@ -26,7 +26,7 @@ public final class StrictnessSelector {
      * @return actual strictness, can be null.
      */
     public static Strictness determineStrictness(
-            Stubbing stubbing, MockCreationSettings mockSettings, Strictness testLevelStrictness) {
+        Stubbing stubbing, MockCreationOptions mockSettings, Strictness testLevelStrictness) {
         if (stubbing != null && stubbing.getStrictness() != null) {
             return stubbing.getStrictness();
         }
diff --git a/src/main/java/org/mockito/internal/stubbing/answers/ClonesArguments.java b/src/main/java/org/mockito/internal/stubbing/answers/ClonesArguments.java
index 0f0c15b91..a01013d43 100644
--- a/src/main/java/org/mockito/internal/stubbing/answers/ClonesArguments.java
+++ b/src/main/java/org/mockito/internal/stubbing/answers/ClonesArguments.java
@@ -7,7 +7,7 @@ package org.mockito.internal.stubbing.answers;
 import java.lang.reflect.Array;
 
 import org.mockito.creation.instance.Instantiator;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.stubbing.defaultanswers.ReturnsEmptyValues;
 import org.mockito.internal.util.reflection.LenientCopyTool;
 import org.mockito.invocation.InvocationOnMock;
@@ -31,7 +31,7 @@ public class ClonesArguments implements Answer<Object> {
                     arguments[i] = newInstance;
                 } else {
                     Instantiator instantiator =
-                            Plugins.getInstantiatorProvider().getInstantiator(null);
+                            PluginRegistry.getInstantiatorProvider().getInstantiator(null);
                     Object newInstance = instantiator.newInstance(from.getClass());
                     new LenientCopyTool().copyToRealObject(from, newInstance);
                     arguments[i] = newInstance;
diff --git a/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java b/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
index c159906af..b5cc85d45 100644
--- a/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
+++ b/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
@@ -15,7 +15,7 @@ import org.mockito.internal.util.MockUtil;
 import org.mockito.internal.util.Primitives;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 public class InvocationInfo implements AbstractAwareMethod {
 
@@ -90,7 +90,7 @@ public class InvocationInfo implements AbstractAwareMethod {
      * E.g:  {@code void foo()} or {@code Void bar()}
      */
     public boolean isVoid() {
-        final MockCreationSettings mockSettings =
+        final MockCreationOptions mockSettings =
                 MockUtil.getMockHandler(invocation.getMock()).getMockSettings();
         Class<?> returnType =
                 GenericMetadataSupport.inferFrom(mockSettings.getTypeToMock())
diff --git a/src/main/java/org/mockito/internal/stubbing/answers/ThrowsExceptionForClassType.java b/src/main/java/org/mockito/internal/stubbing/answers/ThrowsExceptionForClassType.java
index 2c3d92395..2693888ea 100644
--- a/src/main/java/org/mockito/internal/stubbing/answers/ThrowsExceptionForClassType.java
+++ b/src/main/java/org/mockito/internal/stubbing/answers/ThrowsExceptionForClassType.java
@@ -7,7 +7,7 @@ package org.mockito.internal.stubbing.answers;
 import java.io.Serializable;
 
 import org.mockito.creation.instance.Instantiator;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 
 public class ThrowsExceptionForClassType extends AbstractThrowsException implements Serializable {
 
@@ -19,7 +19,7 @@ public class ThrowsExceptionForClassType extends AbstractThrowsException impleme
 
     @Override
     protected Throwable getThrowable() {
-        Instantiator instantiator = Plugins.getInstantiatorProvider().getInstantiator(null);
+        Instantiator instantiator = PluginRegistry.getInstantiatorProvider().getInstantiator(null);
         return instantiator.newInstance(throwableClass);
     }
 }
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ForwardsInvocations.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ForwardsInvocations.java
index 5d12ca03e..3e2238df5 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ForwardsInvocations.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ForwardsInvocations.java
@@ -11,7 +11,7 @@ import java.io.Serializable;
 import java.lang.reflect.InvocationTargetException;
 import java.lang.reflect.Method;
 
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.stubbing.Answer;
@@ -43,7 +43,7 @@ public class ForwardsInvocations implements Answer<Object>, Serializable {
                         mockMethod, delegateMethod, invocation.getMock(), delegatedObject);
             }
 
-            MemberAccessor accessor = Plugins.getMemberAccessor();
+            MemberAccessor accessor = PluginRegistry.getMemberAccessor();
             Object[] rawArguments = invocation.getRawArguments();
             return accessor.invoke(delegateMethod, delegatedObject, rawArguments);
         } catch (NoSuchMethodException e) {
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
index 8b64a1691..cc82ec223 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
@@ -11,7 +11,7 @@ import java.lang.reflect.TypeVariable;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 final class RetrieveGenericsForDefaultAnswers {
 
@@ -35,7 +35,7 @@ final class RetrieveGenericsForDefaultAnswers {
         }
 
         if (type != null) {
-            final MockCreationSettings<?> mockSettings =
+            final MockCreationOptions<?> mockSettings =
                     MockUtil.getMockSettings(invocation.getMock());
             if (!MockUtil.typeMockabilityOf(type, mockSettings.getMockMaker()).mockable()) {
                 return null;
@@ -90,7 +90,7 @@ final class RetrieveGenericsForDefaultAnswers {
     private static Class<?> findTypeFromGeneric(
             final InvocationOnMock invocation, final TypeVariable returnType) {
         // Class level
-        final MockCreationSettings mockSettings =
+        final MockCreationOptions mockSettings =
                 MockUtil.getMockHandler(invocation.getMock()).getMockSettings();
         final GenericMetadataSupport returnTypeSupport =
                 GenericMetadataSupport.inferFrom(mockSettings.getTypeToMock())
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
index 27faed9d9..9c17839e6 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
@@ -12,14 +12,14 @@ import java.io.Serializable;
 
 import org.mockito.MockSettings;
 import org.mockito.Mockito;
-import org.mockito.internal.MockitoCore;
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.MockitoEngine;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.stubbing.StubbedInvocationMatcher;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.Answer;
 
 /**
@@ -51,7 +51,7 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
         GenericMetadataSupport returnTypeGenericMetadata =
                 actualParameterizedType(invocation.getMock())
                         .resolveGenericReturnType(invocation.getMethod());
-        MockCreationSettings<?> mockSettings = MockUtil.getMockSettings(invocation.getMock());
+        MockCreationOptions<?> mockSettings = MockUtil.getMockSettings(invocation.getMock());
 
         Class<?> rawType = returnTypeGenericMetadata.rawType();
         final var emptyValue = ReturnsEmptyValues.returnCommonEmptyValueFor(rawType);
@@ -116,16 +116,16 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
      */
     private Object newDeepStubMock(
             GenericMetadataSupport returnTypeGenericMetadata, Object parentMock) {
-        MockCreationSettings parentMockSettings = MockUtil.getMockSettings(parentMock);
+        MockCreationOptions parentMockSettings = MockUtil.getMockSettings(parentMock);
         return mockitoCore()
-                .mock(
+                .createMock(
                         returnTypeGenericMetadata.rawType(),
                         withSettingsUsing(returnTypeGenericMetadata, parentMockSettings));
     }
 
     private MockSettings withSettingsUsing(
             GenericMetadataSupport returnTypeGenericMetadata,
-            MockCreationSettings<?> parentMockSettings) {
+            MockCreationOptions<?> parentMockSettings) {
         MockSettings mockSettings =
                 returnTypeGenericMetadata.hasRawExtraInterfaces()
                         ? withSettings()
@@ -138,7 +138,7 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
     }
 
     private MockSettings propagateSerializationSettings(
-            MockSettings mockSettings, MockCreationSettings parentMockSettings) {
+            MockSettings mockSettings, MockCreationOptions parentMockSettings) {
         return mockSettings.serializable(parentMockSettings.getSerializableMode());
     }
 
@@ -154,8 +154,8 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
     }
 
     protected GenericMetadataSupport actualParameterizedType(Object mock) {
-        CreationSettings mockSettings =
-                (CreationSettings) MockUtil.getMockHandler(mock).getMockSettings();
+        MockCreationSettings mockSettings =
+                (MockCreationSettings) MockUtil.getMockHandler(mock).getMockSettings();
         return GenericMetadataSupport.inferFrom(mockSettings.getTypeToMock());
     }
 
@@ -202,7 +202,7 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
         }
     }
 
-    private static MockitoCore mockitoCore() {
+    private static MockitoEngine mockitoCore() {
         return LazyHolder.MOCKITO_CORE;
     }
 
@@ -211,7 +211,7 @@ public class ReturnsDeepStubs implements Answer<Object>, Serializable {
     }
 
     private static class LazyHolder {
-        private static final MockitoCore MOCKITO_CORE = new MockitoCore();
+        private static final MockitoEngine MOCKITO_CORE = new MockitoEngine();
         private static final ReturnsEmptyValues DELEGATE = new ReturnsEmptyValues();
     }
 }
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
index c15578091..54be5fdb9 100755
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
@@ -7,10 +7,10 @@ package org.mockito.internal.stubbing.defaultanswers;
 import java.io.Serializable;
 
 import org.mockito.Mockito;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.invocation.InvocationOnMock;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.Answer;
 
 public class ReturnsMocks implements Answer<Object>, Serializable {
@@ -35,12 +35,12 @@ public class ReturnsMocks implements Answer<Object>, Serializable {
                             return null;
                         }
 
-                        MockCreationSettings<?> mockSettings =
+                        MockCreationOptions<?> mockSettings =
                                 MockUtil.getMockSettings(invocation.getMock());
 
                         return Mockito.mock(
                                 type,
-                                new MockSettingsImpl<>()
+                                new DefaultMockSettings<>()
                                         .defaultAnswer(ReturnsMocks.this)
                                         .mockMaker(mockSettings.getMockMaker()));
                     }
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
index d538784a9..526ad9eff 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
@@ -12,13 +12,13 @@ import java.lang.reflect.Method;
 import java.util.Arrays;
 
 import org.mockito.Mockito;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.creation.bytebuddy.MockAccess;
 import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.invocation.Location;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.Answer;
 
 /**
@@ -62,14 +62,14 @@ public class ReturnsSmartNulls implements Answer<Object>, Serializable {
                             return null;
                         }
 
-                        MockCreationSettings<?> mockSettings =
+                        MockCreationOptions<?> mockSettings =
                                 MockUtil.getMockSettings(invocation.getMock());
                         Answer<?> defaultAnswer =
                                 new ThrowsSmartNullPointer(invocation, LocationFactory.create());
 
                         return Mockito.mock(
                                 type,
-                                new MockSettingsImpl<>()
+                                new DefaultMockSettings<>()
                                         .defaultAnswer(defaultAnswer)
                                         .mockMaker(mockSettings.getMockMaker()));
                     }
diff --git a/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java b/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
index 1ad5a757f..f57ef05ae 100644
--- a/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
+++ b/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
@@ -12,7 +12,7 @@ import org.mockito.internal.debugging.InvocationsPrinter;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.Stubbing;
 
 /**
@@ -48,7 +48,7 @@ public class DefaultMockingDetails implements MockingDetails {
     }
 
     @Override
-    public MockCreationSettings<?> getMockCreationSettings() {
+    public MockCreationOptions<?> getMockCreationSettings() {
         return mockHandler().getMockSettings();
     }
 
diff --git a/src/main/java/org/mockito/internal/util/MockNameImpl.java b/src/main/java/org/mockito/internal/util/MockNameImpl.java
deleted file mode 100644
index 637468769..000000000
--- a/src/main/java/org/mockito/internal/util/MockNameImpl.java
+++ /dev/null
@@ -1,59 +0,0 @@
-/*
- * Copyright (c) 2007 Mockito contributors
- * This program is made available under the terms of the MIT License.
- */
-package org.mockito.internal.util;
-
-import java.io.Serializable;
-
-import org.mockito.mock.MockName;
-
-public class MockNameImpl implements MockName, Serializable {
-
-    private static final long serialVersionUID = 8014974700844306925L;
-    private final String mockName;
-    private boolean defaultName;
-
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
-    }
-
-    private static String toInstanceName(Class<?> clazz) {
-        String className = clazz.getSimpleName();
-        if (className.length() == 0) {
-            // it's an anonymous class, let's get name from the parent
-            className = clazz.getSuperclass().getSimpleName();
-        }
-        // lower case first letter
-        return className.substring(0, 1).toLowerCase() + className.substring(1);
-    }
-
-    private static String toClassName(Class<?> clazz) {
-        String className = clazz.getSimpleName();
-        if (className.length() == 0) {
-            // it's an anonymous class, let's get name from the parent
-            className = clazz.getSuperclass().getSimpleName() + "$";
-        }
-        return className + ".class";
-    }
-
-    @Override
-    public boolean isDefault() {
-        return defaultName;
-    }
-
-    @Override
-    public String toString() {
-        return mockName;
-    }
-}
diff --git a/src/main/java/org/mockito/internal/util/MockNameImplementation.java b/src/main/java/org/mockito/internal/util/MockNameImplementation.java
new file mode 100644
index 000000000..20b4c4d43
--- /dev/null
+++ b/src/main/java/org/mockito/internal/util/MockNameImplementation.java
@@ -0,0 +1,59 @@
+/*
+ * Copyright (c) 2007 Mockito contributors
+ * This program is made available under the terms of the MIT License.
+ */
+package org.mockito.internal.util;
+
+import java.io.Serializable;
+
+import org.mockito.mock.MockName;
+
+public class MockNameImplementation implements MockName, Serializable {
+
+    private static final long CLASS_UNIQUE_ID = 8014974700844306925L;
+    private final String simulatedName;
+    private boolean isUsingDefault;
+
+    @SuppressWarnings("unchecked")
+    public MockNameImplementation(String simulatedName, Class<?> targetClass, boolean isStaticMock) {
+        if (simulatedName == null) {
+            this.simulatedName = isStaticMock ? toClassLiteral(targetClass) : toInstanceVariableName(targetClass);
+            this.isUsingDefault = true;
+        } else {
+            this.simulatedName = simulatedName;
+        }
+    }
+
+    public MockNameImplementation(String simulatedName) {
+        this.simulatedName = simulatedName;
+    }
+
+    private static String toInstanceVariableName(Class<?> inputClass) {
+        String simpleName = inputClass.getSimpleName();
+        if (simpleName.length() == 0) {
+            // it's an anonymous class, let's get name from the parent
+            simpleName = inputClass.getSuperclass().getSimpleName();
+        }
+        // lower case first letter
+        return simpleName.substring(0, 1).toLowerCase() + simpleName.substring(1);
+    }
+
+    private static String toClassLiteral(Class<?> inputClass) {
+        String simpleName = inputClass.getSimpleName();
+        if (simpleName.length() == 0) {
+            // it's an anonymous class, let's get name from the parent
+            simpleName = inputClass.getSuperclass().getSimpleName() + "$";
+        }
+        return simpleName + ".class";
+    }
+
+    @Override
+    public boolean isDefault() {
+        return isUsingDefault;
+    }
+
+    @Override
+    public String toString() {
+        return simulatedName;
+    }
+}
diff --git a/src/main/java/org/mockito/internal/util/MockUtil.java b/src/main/java/org/mockito/internal/util/MockUtil.java
index 97b9b49cc..6aab8700c 100644
--- a/src/main/java/org/mockito/internal/util/MockUtil.java
+++ b/src/main/java/org/mockito/internal/util/MockUtil.java
@@ -7,13 +7,13 @@ package org.mockito.internal.util;
 import org.mockito.MockedConstruction;
 import org.mockito.Mockito;
 import org.mockito.exceptions.misusing.NotAMockException;
-import org.mockito.internal.configuration.plugins.DefaultMockitoPlugins;
-import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.util.reflection.LenientCopyTool;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.mock.MockName;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockMaker.TypeMockability;
@@ -29,7 +29,7 @@ import static org.mockito.internal.handler.MockHandlerFactory.createMockHandler;
 @SuppressWarnings("unchecked")
 public class MockUtil {
 
-    private static final MockMaker defaultMockMaker = Plugins.getMockMaker();
+    private static final MockMaker defaultMockMaker = PluginRegistry.getMockMaker();
     private static final Map<Class<? extends MockMaker>, MockMaker> mockMakers =
             new ConcurrentHashMap<>(
                     Collections.singletonMap(defaultMockMaker.getClass(), defaultMockMaker));
@@ -42,8 +42,8 @@ public class MockUtil {
         }
 
         String typeName;
-        if (DefaultMockitoPlugins.MOCK_MAKER_ALIASES.contains(mockMaker)) {
-            typeName = DefaultMockitoPlugins.getDefaultPluginClass(mockMaker);
+        if (DefaultMockitoPluginRegistry.MOCK_MAKER_ALIASES.contains(mockMaker)) {
+            typeName = DefaultMockitoPluginRegistry.getDefaultPluginClass(mockMaker);
         } else {
             typeName = mockMaker;
         }
@@ -78,7 +78,7 @@ public class MockUtil {
         return getMockMaker(mockMaker).isTypeMockable(type);
     }
 
-    public static <T> T createMock(MockCreationSettings<T> settings) {
+    public static <T> T createMock(MockCreationOptions<T> settings) {
         MockMaker mockMaker = getMockMaker(settings.getMockMaker());
         MockHandler mockHandler = createMockHandler(settings);
 
@@ -104,7 +104,7 @@ public class MockUtil {
 
     public static void resetMock(Object mock) {
         MockHandler oldHandler = getMockHandler(mock);
-        MockCreationSettings settings = oldHandler.getMockSettings();
+        MockCreationOptions settings = oldHandler.getMockSettings();
         MockHandler newHandler = createMockHandler(settings);
 
         mock = resolve(mock);
@@ -168,7 +168,7 @@ public class MockUtil {
         if (mock instanceof Class<?>) { // static mocks are resolved by definition
             return mock;
         }
-        for (MockResolver mockResolver : Plugins.getMockResolvers()) {
+        for (MockResolver mockResolver : PluginRegistry.getMockResolvers()) {
             mock = mockResolver.resolve(mock);
         }
         return mock;
@@ -185,18 +185,18 @@ public class MockUtil {
     public static void maybeRedefineMockName(Object mock, String newName) {
         MockName mockName = getMockName(mock);
         // TODO SF hacky...
-        MockCreationSettings mockSettings = getMockHandler(mock).getMockSettings();
-        if (mockName.isDefault() && mockSettings instanceof CreationSettings) {
-            ((CreationSettings) mockSettings).setMockName(new MockNameImpl(newName));
+        MockCreationOptions mockSettings = getMockHandler(mock).getMockSettings();
+        if (mockName.isDefault() && mockSettings instanceof MockCreationSettings) {
+            ((MockCreationSettings) mockSettings).setMockName(new MockNameImplementation(newName));
         }
     }
 
-    public static MockCreationSettings getMockSettings(Object mock) {
+    public static MockCreationOptions getMockSettings(Object mock) {
         return getMockHandler(mock).getMockSettings();
     }
 
     public static <T> MockMaker.StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings) {
+            Class<T> type, MockCreationOptions<T> settings) {
         MockMaker mockMaker = getMockMaker(settings.getMockMaker());
         MockHandler<T> handler = createMockHandler(settings);
         return mockMaker.createStaticMock(type, settings, handler);
@@ -204,7 +204,7 @@ public class MockUtil {
 
     public static <T> MockMaker.ConstructionMockControl<T> createConstructionMock(
             Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
+            Function<MockedConstruction.Context, MockCreationOptions<T>> settingsFactory,
             MockedConstruction.MockInitializer<T> mockInitializer) {
         Function<MockedConstruction.Context, MockHandler<T>> handlerFactory =
                 context -> createMockHandler(settingsFactory.apply(context));
diff --git a/src/main/java/org/mockito/internal/util/reflection/BeanPropertySetter.java b/src/main/java/org/mockito/internal/util/reflection/BeanPropertySetter.java
index d904f62a5..44aee82b6 100644
--- a/src/main/java/org/mockito/internal/util/reflection/BeanPropertySetter.java
+++ b/src/main/java/org/mockito/internal/util/reflection/BeanPropertySetter.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.util.reflection;
 
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.MemberAccessor;
 
 import java.lang.reflect.Field;
@@ -54,7 +54,7 @@ public class BeanPropertySetter {
      */
     public boolean set(final Object value) {
 
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor accessor = PluginRegistry.getMemberAccessor();
         Method writeMethod = null;
         try {
             writeMethod = target.getClass().getMethod(setterName(field.getName()), field.getType());
diff --git a/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java b/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
index 7d51a6bb1..b491a2653 100644
--- a/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
+++ b/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
@@ -5,7 +5,7 @@
 package org.mockito.internal.util.reflection;
 
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.util.MockUtil;
 import org.mockito.plugins.MemberAccessor;
 
@@ -137,7 +137,7 @@ public class FieldInitializer {
     }
 
     private FieldInitializationReport acquireFieldInstance() throws IllegalAccessException {
-        final MemberAccessor accessor = Plugins.getMemberAccessor();
+        final MemberAccessor accessor = PluginRegistry.getMemberAccessor();
         Object fieldInstance = accessor.get(field, fieldOwner);
         if (fieldInstance != null) {
             return new FieldInitializationReport(fieldInstance, false, false);
@@ -195,7 +195,7 @@ public class FieldInitializer {
 
         @Override
         public FieldInitializationReport instantiate() {
-            final MemberAccessor invoker = Plugins.getMemberAccessor();
+            final MemberAccessor invoker = PluginRegistry.getMemberAccessor();
             try {
                 Constructor<?> constructor = field.getType().getDeclaredConstructor();
 
@@ -284,7 +284,7 @@ public class FieldInitializer {
 
         @Override
         public FieldInitializationReport instantiate() {
-            final MemberAccessor accessor = Plugins.getMemberAccessor();
+            final MemberAccessor accessor = PluginRegistry.getMemberAccessor();
             Constructor<?> constructor = biggestConstructor(field.getType());
             final Object[] args = argResolver.resolveTypeInstances(constructor.getParameterTypes());
             try {
diff --git a/src/main/java/org/mockito/internal/util/reflection/FieldReader.java b/src/main/java/org/mockito/internal/util/reflection/FieldReader.java
index 6c3c120ee..3dd854f6a 100644
--- a/src/main/java/org/mockito/internal/util/reflection/FieldReader.java
+++ b/src/main/java/org/mockito/internal/util/reflection/FieldReader.java
@@ -7,14 +7,14 @@ package org.mockito.internal.util.reflection;
 import java.lang.reflect.Field;
 
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.MemberAccessor;
 
 public class FieldReader {
 
     final Object target;
     final Field field;
-    final MemberAccessor accessor = Plugins.getMemberAccessor();
+    final MemberAccessor accessor = PluginRegistry.getMemberAccessor();
 
     public FieldReader(Object target, Field field) {
         this.target = target;
diff --git a/src/main/java/org/mockito/internal/util/reflection/InstanceField.java b/src/main/java/org/mockito/internal/util/reflection/InstanceField.java
index ffefaec2a..900937d9c 100644
--- a/src/main/java/org/mockito/internal/util/reflection/InstanceField.java
+++ b/src/main/java/org/mockito/internal/util/reflection/InstanceField.java
@@ -8,7 +8,7 @@ import java.lang.annotation.Annotation;
 import java.lang.reflect.Field;
 
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.util.Checks;
 import org.mockito.plugins.MemberAccessor;
 
@@ -50,7 +50,7 @@ public class InstanceField {
      * @param value The value that should be written to the field.
      */
     public void set(Object value) {
-        MemberAccessor accessor = Plugins.getMemberAccessor();
+        MemberAccessor accessor = PluginRegistry.getMemberAccessor();
         try {
             accessor.set(field, instance, value);
         } catch (IllegalAccessException e) {
diff --git a/src/main/java/org/mockito/internal/util/reflection/LenientCopyTool.java b/src/main/java/org/mockito/internal/util/reflection/LenientCopyTool.java
index 95b30198d..462fb12bc 100644
--- a/src/main/java/org/mockito/internal/util/reflection/LenientCopyTool.java
+++ b/src/main/java/org/mockito/internal/util/reflection/LenientCopyTool.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.util.reflection;
 
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.MemberAccessor;
 
 import java.lang.reflect.Field;
@@ -12,7 +12,7 @@ import java.lang.reflect.Modifier;
 
 public class LenientCopyTool {
 
-    MemberAccessor accessor = Plugins.getMemberAccessor();
+    MemberAccessor accessor = PluginRegistry.getMemberAccessor();
 
     public <T> void copyToMock(T from, T mock) {
         copy(from, mock, from.getClass());
diff --git a/src/main/java/org/mockito/invocation/InvocationFactory.java b/src/main/java/org/mockito/invocation/InvocationFactory.java
index c28ef716b..ebda8a7fb 100644
--- a/src/main/java/org/mockito/invocation/InvocationFactory.java
+++ b/src/main/java/org/mockito/invocation/InvocationFactory.java
@@ -8,7 +8,7 @@ import java.io.Serializable;
 import java.lang.reflect.Method;
 
 import org.mockito.MockitoFramework;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * Available via {@link MockitoFramework#getInvocationFactory()}.
@@ -18,7 +18,7 @@ import org.mockito.mock.MockCreationSettings;
  * <p>
  * Please don't provide your own implementation of {@link Invocation} type.
  * Mockito team needs flexibility to add new methods to this interface if we need to.
- * If you integrate Mockito framework and you need an instance of {@link Invocation}, use {@link #createInvocation(Object, MockCreationSettings, Method, RealMethodBehavior, Object...)}.
+ * If you integrate Mockito framework and you need an instance of {@link Invocation}, use {@link #createInvocation(Object, MockCreationOptions, Method, RealMethodBehavior, Object...)}.
  *
  * @since 2.10.0
  */
@@ -49,7 +49,7 @@ public interface InvocationFactory {
      */
     Invocation createInvocation(
             Object target,
-            MockCreationSettings settings,
+            MockCreationOptions settings,
             Method method,
             RealMethodBehavior realMethod,
             Object... args);
diff --git a/src/main/java/org/mockito/invocation/MockHandler.java b/src/main/java/org/mockito/invocation/MockHandler.java
index 56a0004ad..2c5761896 100644
--- a/src/main/java/org/mockito/invocation/MockHandler.java
+++ b/src/main/java/org/mockito/invocation/MockHandler.java
@@ -7,7 +7,7 @@ package org.mockito.invocation;
 import java.io.Serializable;
 
 import org.mockito.MockSettings;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * Mockito handler of an invocation on a mock. This is a core part of the API, the heart of Mockito.
@@ -15,8 +15,8 @@ import org.mockito.mock.MockCreationSettings;
  * Handler can be used to programmatically simulate invocations on the mock object.
  * <p>
  * Mockito will provide you with the implementation of this interface via {@link org.mockito.plugins.MockMaker} methods:
- * {@link org.mockito.plugins.MockMaker#createMock(MockCreationSettings, MockHandler)}
- * and {@link org.mockito.plugins.MockMaker#resetMock(Object, MockHandler, MockCreationSettings)}.
+ * {@link org.mockito.plugins.MockMaker#createMock(MockCreationOptions, MockHandler)}
+ * and {@link org.mockito.plugins.MockMaker#resetMock(Object, MockHandler, MockCreationOptions)}.
  * <p>
  * You can provide your own implementation of MockHandler but make sure that the right instance is returned by
  * {@link org.mockito.plugins.MockMaker#getHandler(Object)}.
@@ -43,7 +43,7 @@ public interface MockHandler<T> extends Serializable {
      * @return read-only settings of the mock
      * @since 2.10.0
      */
-    MockCreationSettings<T> getMockSettings();
+    MockCreationOptions<T> getMockSettings();
 
     /**
      * Returns the object that holds all invocations on the mock object,
diff --git a/src/main/java/org/mockito/junit/MockitoJUnit.java b/src/main/java/org/mockito/junit/MockitoJUnit.java
index bbe61308f..58fda4e66 100644
--- a/src/main/java/org/mockito/junit/MockitoJUnit.java
+++ b/src/main/java/org/mockito/junit/MockitoJUnit.java
@@ -5,7 +5,7 @@
 package org.mockito.junit;
 
 import org.junit.rules.TestRule;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.junit.JUnitRule;
 import org.mockito.internal.junit.JUnitTestRule;
 import org.mockito.internal.junit.VerificationCollectorImpl;
@@ -31,7 +31,7 @@ public final class MockitoJUnit {
      * @since 1.10.17
      */
     public static MockitoRule rule() {
-        return new JUnitRule(Plugins.getMockitoLogger(), Strictness.WARN);
+        return new JUnitRule(PluginRegistry.getMockitoLogger(), Strictness.WARN);
     }
 
     /**
@@ -45,7 +45,7 @@ public final class MockitoJUnit {
      * @since 3.3.0
      */
     public static MockitoTestRule testRule(Object testInstance) {
-        return new JUnitTestRule(Plugins.getMockitoLogger(), Strictness.WARN, testInstance);
+        return new JUnitTestRule(PluginRegistry.getMockitoLogger(), Strictness.WARN, testInstance);
     }
 
     /**
diff --git a/src/main/java/org/mockito/listeners/MockCreationListener.java b/src/main/java/org/mockito/listeners/MockCreationListener.java
index 7ab15f823..ad59543bf 100644
--- a/src/main/java/org/mockito/listeners/MockCreationListener.java
+++ b/src/main/java/org/mockito/listeners/MockCreationListener.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.listeners;
 
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * Notified when mock object is created.
@@ -18,7 +18,7 @@ public interface MockCreationListener extends MockitoListener {
      * @param mock created mock object
      * @param settings the settings used for creation
      */
-    void onMockCreated(Object mock, MockCreationSettings settings);
+    void onMockCreated(Object mock, MockCreationOptions settings);
 
     /**
      * Static mock object was just created.
@@ -26,5 +26,5 @@ public interface MockCreationListener extends MockitoListener {
      * @param mock the type being mocked
      * @param settings the settings used for creation
      */
-    default void onStaticMockCreated(Class<?> mock, MockCreationSettings settings) {}
+    default void onStaticMockCreated(Class<?> mock, MockCreationOptions settings) {}
 }
diff --git a/src/main/java/org/mockito/listeners/StubbingLookupEvent.java b/src/main/java/org/mockito/listeners/StubbingLookupEvent.java
index 30642cca6..e7a472bdc 100644
--- a/src/main/java/org/mockito/listeners/StubbingLookupEvent.java
+++ b/src/main/java/org/mockito/listeners/StubbingLookupEvent.java
@@ -7,7 +7,7 @@ package org.mockito.listeners;
 import java.util.Collection;
 
 import org.mockito.invocation.Invocation;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.Stubbing;
 
 /**
@@ -39,5 +39,5 @@ public interface StubbingLookupEvent {
      * @return Settings of the mock object that we are invoking
      * @since 2.24.6
      */
-    MockCreationSettings getMockSettings();
+    MockCreationOptions getMockSettings();
 }
diff --git a/src/main/java/org/mockito/listeners/StubbingLookupListener.java b/src/main/java/org/mockito/listeners/StubbingLookupListener.java
index b33e06346..87f83c4a5 100644
--- a/src/main/java/org/mockito/listeners/StubbingLookupListener.java
+++ b/src/main/java/org/mockito/listeners/StubbingLookupListener.java
@@ -5,7 +5,7 @@
 package org.mockito.listeners;
 
 import org.mockito.MockSettings;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * When a method is called on a mock object Mockito looks up any stubbings recorded on that mock.
@@ -19,7 +19,7 @@ import org.mockito.mock.MockCreationSettings;
  * If the answer is not found (e.g. that invocation was not stubbed on the mock), mock's default answer is used.
  * This listener implementation is notified when Mockito attempts to find an answer for invocation on a mock.
  * <p>
- * The listeners can be accessed via {@link MockCreationSettings#getStubbingLookupListeners()}.
+ * The listeners can be accessed via {@link MockCreationOptions#getStubbingLookupListeners()}.
  *
  * @since 2.24.6
  */
diff --git a/src/main/java/org/mockito/mock/MockCreationSettings.java b/src/main/java/org/mockito/mock/MockCreationOptions.java
similarity index 97%
rename from src/main/java/org/mockito/mock/MockCreationSettings.java
rename to src/main/java/org/mockito/mock/MockCreationOptions.java
index 949af03b2..9c7823740 100644
--- a/src/main/java/org/mockito/mock/MockCreationSettings.java
+++ b/src/main/java/org/mockito/mock/MockCreationOptions.java
@@ -21,7 +21,7 @@ import org.mockito.stubbing.Answer;
  * Informs about the mock settings. An immutable view of {@link org.mockito.MockSettings}.
  */
 @NotExtensible
-public interface MockCreationSettings<T> {
+public interface MockCreationOptions<T> {
 
     /**
      * Mocked type. An interface or class the mock should implement / extend.
@@ -125,7 +125,7 @@ public interface MockCreationSettings<T> {
     Object getOuterClassInstance();
 
     /**
-     *  @deprecated Use {@link MockCreationSettings#getStrictness()} instead.
+     *  @deprecated Use {@link MockCreationOptions#getStrictness()} instead.
      *
      * Informs if the mock was created with "lenient" strictness, e.g. having {@link Strictness#LENIENT} characteristic.
      * For more information about using mocks with lenient strictness, see {@link MockSettings#lenient()}.
diff --git a/src/main/java/org/mockito/plugins/DoNotMockEnforcer.java b/src/main/java/org/mockito/plugins/DoNotMockChecker.java
similarity index 83%
rename from src/main/java/org/mockito/plugins/DoNotMockEnforcer.java
rename to src/main/java/org/mockito/plugins/DoNotMockChecker.java
index a033bbce5..61205564a 100644
--- a/src/main/java/org/mockito/plugins/DoNotMockEnforcer.java
+++ b/src/main/java/org/mockito/plugins/DoNotMockChecker.java
@@ -7,7 +7,7 @@ package org.mockito.plugins;
 /**
  * Enforcer that is applied to every type in the type hierarchy of the class-to-be-mocked.
  */
-public interface DoNotMockEnforcer {
+public interface DoNotMockChecker {
 
     /**
      * If this type is allowed to be mocked. Return an empty optional if the enforcer allows
@@ -16,8 +16,8 @@ public interface DoNotMockEnforcer {
      * Note that Mockito performs traversal of the type hierarchy. Implementations of this class
      * should therefore not perform type traversal themselves but rely on Mockito.
      *
-     * @param type The type to check
+     * @param targetClass The type to check
      * @return Optional message if this type can not be mocked, or an empty optional if type can be mocked
      */
-    String checkTypeForDoNotMockViolation(Class<?> type);
+    String checkTypeForDoNotMockRuleViolation(Class<?> targetClass);
 }
diff --git a/src/main/java/org/mockito/plugins/InstantiatorProvider2.java b/src/main/java/org/mockito/plugins/InstantiatorProvider2.java
index 3bc1f322c..7df3f1ce3 100644
--- a/src/main/java/org/mockito/plugins/InstantiatorProvider2.java
+++ b/src/main/java/org/mockito/plugins/InstantiatorProvider2.java
@@ -5,7 +5,7 @@
 package org.mockito.plugins;
 
 import org.mockito.creation.instance.Instantiator;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * <p>
@@ -54,5 +54,5 @@ public interface InstantiatorProvider2 {
      *
      * @since 2.15.4
      */
-    Instantiator getInstantiator(MockCreationSettings<?> settings);
+    Instantiator getInstantiator(MockCreationOptions<?> settings);
 }
diff --git a/src/main/java/org/mockito/plugins/MockMaker.java b/src/main/java/org/mockito/plugins/MockMaker.java
index c0b1cbcd2..f0c4b30f1 100644
--- a/src/main/java/org/mockito/plugins/MockMaker.java
+++ b/src/main/java/org/mockito/plugins/MockMaker.java
@@ -8,7 +8,7 @@ import org.mockito.MockSettings;
 import org.mockito.MockedConstruction;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 import java.util.List;
 import java.util.Optional;
@@ -59,7 +59,7 @@ import static org.mockito.internal.util.StringUtil.join;
  *             .mockMaker("org.awesome.mockito.AwesomeMockMaker"));
  * </pre>
  *
- * @see org.mockito.mock.MockCreationSettings
+ * @see MockCreationOptions
  * @see org.mockito.invocation.MockHandler
  * @since 1.9.5
  */
@@ -85,7 +85,7 @@ public interface MockMaker {
      * @return The mock instance.
      * @since 1.9.5
      */
-    <T> T createMock(MockCreationSettings<T> settings, MockHandler handler);
+    <T> T createMock(MockCreationOptions<T> settings, MockHandler handler);
 
     /**
      * By implementing this method, a mock maker can optionally support the creation of spies where all fields
@@ -102,7 +102,7 @@ public interface MockMaker {
      * @since 3.5.0
      */
     default <T> Optional<T> createSpy(
-            MockCreationSettings<T> settings, MockHandler handler, T instance) {
+        MockCreationOptions<T> settings, MockHandler handler, T instance) {
         return Optional.empty();
     }
 
@@ -132,7 +132,7 @@ public interface MockMaker {
      * @param settings The mock settings - should you need to access some of the mock creation details.
      * @since 1.9.5
      */
-    void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings);
+    void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings);
 
     /**
      * Indicates if the given type can be mocked by this mockmaker.
@@ -164,7 +164,7 @@ public interface MockMaker {
      * @since 3.4.0
      */
     default <T> StaticMockControl<T> createStaticMock(
-            Class<T> type, MockCreationSettings<T> settings, MockHandler handler) {
+        Class<T> type, MockCreationOptions<T> settings, MockHandler handler) {
         throw new MockitoException(
                 join(
                         "The used MockMaker "
@@ -194,7 +194,7 @@ public interface MockMaker {
      */
     default <T> ConstructionMockControl<T> createConstructionMock(
             Class<T> type,
-            Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
+            Function<MockedConstruction.Context, MockCreationOptions<T>> settingsFactory,
             Function<MockedConstruction.Context, MockHandler<T>> handlerFactory,
             MockedConstruction.MockInitializer<T> mockInitializer) {
         throw new MockitoException(
diff --git a/src/test/java/org/mockito/MockitoEnvTest.java b/src/test/java/org/mockito/MockitoEnvTest.java
index 1a162e939..1c68498ae 100644
--- a/src/test/java/org/mockito/MockitoEnvTest.java
+++ b/src/test/java/org/mockito/MockitoEnvTest.java
@@ -11,8 +11,8 @@ import static org.hamcrest.CoreMatchers.nullValue;
 
 import org.junit.Assume;
 import org.junit.Test;
-import org.mockito.internal.configuration.plugins.DefaultMockitoPlugins;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
 
@@ -23,8 +23,8 @@ public class MockitoEnvTest {
         Assume.assumeThat(mockMaker, not(nullValue()));
         Assume.assumeThat(mockMaker, endsWith("default"));
 
-        assertThat(DefaultMockitoPlugins.getDefaultPluginClass(MockMaker.class.getName()))
-                .isEqualTo(Plugins.getMockMaker().getClass().getName());
+        assertThat(DefaultMockitoPluginRegistry.getDefaultPluginClass(MockMaker.class.getName()))
+                .isEqualTo(PluginRegistry.getMockMaker().getClass().getName());
     }
 
     @Test
@@ -33,8 +33,8 @@ public class MockitoEnvTest {
         Assume.assumeThat(mockMaker, not(nullValue()));
         Assume.assumeThat(mockMaker, not(endsWith("default")));
 
-        assertThat(DefaultMockitoPlugins.getDefaultPluginClass(mockMaker))
-                .isEqualTo(Plugins.getMockMaker().getClass().getName());
+        assertThat(DefaultMockitoPluginRegistry.getDefaultPluginClass(mockMaker))
+                .isEqualTo(PluginRegistry.getMockMaker().getClass().getName());
     }
 
     @Test
@@ -43,8 +43,8 @@ public class MockitoEnvTest {
         Assume.assumeThat(memberAccessor, not(nullValue()));
         Assume.assumeThat(memberAccessor, endsWith("default"));
 
-        assertThat(DefaultMockitoPlugins.getDefaultPluginClass(MemberAccessor.class.getName()))
-                .isEqualTo(Plugins.getMemberAccessor().getClass().getName());
+        assertThat(DefaultMockitoPluginRegistry.getDefaultPluginClass(MemberAccessor.class.getName()))
+                .isEqualTo(PluginRegistry.getMemberAccessor().getClass().getName());
     }
 
     @Test
@@ -53,7 +53,7 @@ public class MockitoEnvTest {
         Assume.assumeThat(memberAccessor, not(nullValue()));
         Assume.assumeThat(memberAccessor, not(endsWith("default")));
 
-        assertThat(DefaultMockitoPlugins.getDefaultPluginClass(memberAccessor))
-                .isEqualTo(Plugins.getMemberAccessor().getClass().getName());
+        assertThat(DefaultMockitoPluginRegistry.getDefaultPluginClass(memberAccessor))
+                .isEqualTo(PluginRegistry.getMemberAccessor().getClass().getName());
     }
 }
diff --git a/src/test/java/org/mockito/MockitoTest.java b/src/test/java/org/mockito/MockitoTest.java
index 1671280d0..bdfe80f4c 100644
--- a/src/test/java/org/mockito/MockitoTest.java
+++ b/src/test/java/org/mockito/MockitoTest.java
@@ -19,8 +19,8 @@ import org.junit.Test;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.misusing.NotAMockException;
 import org.mockito.exceptions.misusing.NullInsteadOfMockException;
-import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.plugins.InlineMockMaker;
 
@@ -105,7 +105,7 @@ public class MockitoTest {
     @SuppressWarnings({"CheckReturnValue", "MockitoUsage"})
     @Test
     public void shouldGiveExplanationOnStaticMockingWithoutInlineMockMaker() {
-        Assume.assumeThat(Plugins.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
 
         assertThatThrownBy(
                         () -> {
@@ -122,7 +122,7 @@ public class MockitoTest {
     @SuppressWarnings({"CheckReturnValue", "MockitoUsage"})
     @Test
     public void shouldGiveExplanationOnConstructionMockingWithoutInlineMockMaker() {
-        Assume.assumeThat(Plugins.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
 
         assertThatThrownBy(
                         () -> {
@@ -139,7 +139,7 @@ public class MockitoTest {
     @SuppressWarnings({"CheckReturnValue", "MockitoUsage"})
     @Test
     public void shouldGiveExplanationOnConstructionMockingWithInlineMockMaker() {
-        Assume.assumeThat(Plugins.getMockMaker(), instanceOf(InlineMockMaker.class));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), instanceOf(InlineMockMaker.class));
 
         assertThatThrownBy(
                         () -> {
@@ -153,7 +153,7 @@ public class MockitoTest {
     @Test
     public void shouldStartingMockSettingsContainDefaultBehavior() {
         // given
-        MockSettingsImpl<?> settings = (MockSettingsImpl<?>) Mockito.withSettings();
+        DefaultMockSettings<?> settings = (DefaultMockSettings<?>) Mockito.withSettings();
 
         // when / then
         assertThat(settings.getDefaultAnswer()).isEqualTo(Mockito.RETURNS_DEFAULTS);
diff --git a/src/test/java/org/mockito/internal/configuration/GlobalConfigurationTest.java b/src/test/java/org/mockito/internal/configuration/GlobalConfigurationTest.java
index 48cf998b0..251efe9e1 100644
--- a/src/test/java/org/mockito/internal/configuration/GlobalConfigurationTest.java
+++ b/src/test/java/org/mockito/internal/configuration/GlobalConfigurationTest.java
@@ -11,7 +11,7 @@ import org.assertj.core.api.Assertions;
 import org.junit.After;
 import org.junit.Test;
 import org.mockito.Mockito;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockitoutil.ClassLoaders;
 import org.objenesis.Objenesis;
 
@@ -35,7 +35,7 @@ public class GlobalConfigurationTest {
                             @Override
                             public void run() {
                                 assertThat(new GlobalConfiguration().tryGetPluginAnnotationEngine())
-                                        .isInstanceOf(Plugins.getAnnotationEngine().getClass());
+                                        .isInstanceOf(PluginRegistry.getAnnotationEngine().getClass());
                             }
                         });
     }
diff --git a/src/test/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginsTest.java b/src/test/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginsTest.java
index 01024f627..bf8e352f3 100644
--- a/src/test/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginsTest.java
+++ b/src/test/java/org/mockito/internal/configuration/plugins/DefaultMockitoPluginsTest.java
@@ -5,9 +5,9 @@
 package org.mockito.internal.configuration.plugins;
 
 import static org.junit.Assert.*;
-import static org.mockito.internal.configuration.plugins.DefaultMockitoPlugins.INLINE_ALIAS;
-import static org.mockito.internal.configuration.plugins.DefaultMockitoPlugins.PROXY_ALIAS;
-import static org.mockito.internal.configuration.plugins.DefaultMockitoPlugins.SUBCLASS_ALIAS;
+import static org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry.INLINE_MAPPING;
+import static org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry.PROXY_MAPPING;
+import static org.mockito.internal.configuration.plugins.DefaultMockitoPluginRegistry.SUBCLASS_MAPPING;
 
 import org.assertj.core.api.Assertions;
 import org.junit.Test;
@@ -23,20 +23,20 @@ import org.mockitoutil.TestBase;
 
 public class DefaultMockitoPluginsTest extends TestBase {
 
-    private final DefaultMockitoPlugins plugins = new DefaultMockitoPlugins();
+    private final DefaultMockitoPluginRegistry plugins = new DefaultMockitoPluginRegistry();
 
     @Test
     public void provides_plugins() throws Exception {
         assertEquals(
                 "org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker",
-                DefaultMockitoPlugins.getDefaultPluginClass(INLINE_ALIAS));
+                DefaultMockitoPluginRegistry.getDefaultPluginClass(INLINE_MAPPING));
         assertEquals(InlineByteBuddyMockMaker.class, plugins.getInlineMockMaker().getClass());
         assertEquals(
                 "org.mockito.internal.creation.proxy.ProxyMockMaker",
-                DefaultMockitoPlugins.getDefaultPluginClass(PROXY_ALIAS));
+                DefaultMockitoPluginRegistry.getDefaultPluginClass(PROXY_MAPPING));
         assertEquals(
                 "org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker",
-                DefaultMockitoPlugins.getDefaultPluginClass(SUBCLASS_ALIAS));
+                DefaultMockitoPluginRegistry.getDefaultPluginClass(SUBCLASS_MAPPING));
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
diff --git a/src/test/java/org/mockito/internal/creation/AbstractMockMakerTest.java b/src/test/java/org/mockito/internal/creation/AbstractMockMakerTest.java
index d59477829..e314172c4 100644
--- a/src/test/java/org/mockito/internal/creation/AbstractMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/AbstractMockMakerTest.java
@@ -10,7 +10,7 @@ import org.mockito.internal.stubbing.answers.CallsRealMethods;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationContainer;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 import org.mockito.stubbing.Answer;
@@ -43,7 +43,7 @@ public abstract class AbstractMockMakerTest<MM extends MockMaker, C> {
 
     @Test
     public void should_reset_mock_and_set_new_handler() throws Throwable {
-        MockCreationSettings<C> settings = settingsWithSuperCall(target);
+        MockCreationOptions<C> settings = settingsWithSuperCall(target);
         C proxy = mockMaker.createMock(settings, new MockHandlerImpl<C>(settings));
 
         MockHandler handler = new MockHandlerImpl<C>(settings);
@@ -51,30 +51,30 @@ public abstract class AbstractMockMakerTest<MM extends MockMaker, C> {
         assertThat(mockMaker.getHandler(proxy)).isSameAs(handler);
     }
 
-    protected static <T> MockCreationSettings<T> settingsFor(
+    protected static <T> MockCreationOptions<T> settingsFor(
             Class<T> type, Class<?>... extraInterfaces) {
-        MockSettingsImpl<T> mockSettings = new MockSettingsImpl<T>();
+        DefaultMockSettings<T> mockSettings = new DefaultMockSettings<T>();
         mockSettings.setTypeToMock(type);
         if (extraInterfaces.length > 0) mockSettings.extraInterfaces(extraInterfaces);
         return mockSettings;
     }
 
-    protected static <T> MockCreationSettings<T> serializableSettingsFor(
+    protected static <T> MockCreationOptions<T> serializableSettingsFor(
             Class<T> type, SerializableMode serializableMode) {
-        MockSettingsImpl<T> mockSettings = new MockSettingsImpl<T>();
+        DefaultMockSettings<T> mockSettings = new DefaultMockSettings<T>();
         mockSettings.serializable(serializableMode);
         mockSettings.setTypeToMock(type);
         return mockSettings;
     }
 
-    protected static <T> MockCreationSettings<T> settingsWithConstructorFor(Class<T> type) {
-        MockSettingsImpl<T> mockSettings = new MockSettingsImpl<T>();
+    protected static <T> MockCreationOptions<T> settingsWithConstructorFor(Class<T> type) {
+        DefaultMockSettings<T> mockSettings = new DefaultMockSettings<T>();
         mockSettings.setTypeToMock(type);
         return mockSettings;
     }
 
-    protected static <T> MockCreationSettings<T> settingsWithSuperCall(Class<T> type) {
-        MockSettingsImpl<T> mockSettings = new MockSettingsImpl<T>();
+    protected static <T> MockCreationOptions<T> settingsWithSuperCall(Class<T> type) {
+        DefaultMockSettings<T> mockSettings = new DefaultMockSettings<T>();
         mockSettings.setTypeToMock(type);
         mockSettings.defaultAnswer(new CallsRealMethods());
         return mockSettings;
@@ -89,7 +89,7 @@ public abstract class AbstractMockMakerTest<MM extends MockMaker, C> {
             return null;
         }
 
-        public MockCreationSettings<Object> getMockSettings() {
+        public MockCreationOptions<Object> getMockSettings() {
             return null;
         }
 
diff --git a/src/test/java/org/mockito/internal/creation/MockSettingsImplTest.java b/src/test/java/org/mockito/internal/creation/MockSettingsImplTest.java
index dc8af3542..259b31d46 100644
--- a/src/test/java/org/mockito/internal/creation/MockSettingsImplTest.java
+++ b/src/test/java/org/mockito/internal/creation/MockSettingsImplTest.java
@@ -21,7 +21,7 @@ import org.mockitoutil.TestBase;
 
 public class MockSettingsImplTest extends TestBase {
 
-    private MockSettingsImpl<?> mockSettingsImpl = new MockSettingsImpl<Object>();
+    private DefaultMockSettings<?> mockSettingsImpl = new DefaultMockSettings<Object>();
 
     @Mock private InvocationListener invocationListener;
     @Mock private StubbingLookupListener stubbingLookupListener;
@@ -121,7 +121,7 @@ public class MockSettingsImplTest extends TestBase {
     @Test
     public void shouldAddVerboseLoggingListener() {
         // given
-        assertThat(mockSettingsImpl.hasInvocationListeners()).isFalse();
+        assertThat(mockSettingsImpl.hasAnyInvocationListeners()).isFalse();
 
         // when
         mockSettingsImpl.verboseLogging();
@@ -135,7 +135,7 @@ public class MockSettingsImplTest extends TestBase {
     @Test
     public void shouldAddVerboseLoggingListenerOnlyOnce() {
         // given
-        assertThat(mockSettingsImpl.hasInvocationListeners()).isFalse();
+        assertThat(mockSettingsImpl.hasAnyInvocationListeners()).isFalse();
 
         // when
         mockSettingsImpl.verboseLogging().verboseLogging();
@@ -148,7 +148,7 @@ public class MockSettingsImplTest extends TestBase {
     @SuppressWarnings("unchecked")
     public void shouldAddInvocationListener() {
         // given
-        assertThat(mockSettingsImpl.hasInvocationListeners()).isFalse();
+        assertThat(mockSettingsImpl.hasAnyInvocationListeners()).isFalse();
 
         // when
         mockSettingsImpl.invocationListeners(invocationListener);
@@ -161,7 +161,7 @@ public class MockSettingsImplTest extends TestBase {
     @SuppressWarnings("unchecked")
     public void canAddDuplicateInvocationListeners_ItsNotOurBusinessThere() {
         // given
-        assertThat(mockSettingsImpl.hasInvocationListeners()).isFalse();
+        assertThat(mockSettingsImpl.hasAnyInvocationListeners()).isFalse();
 
         // when
         mockSettingsImpl
@@ -177,19 +177,19 @@ public class MockSettingsImplTest extends TestBase {
     public void validates_listeners() {
         assertThatThrownBy(
                         () ->
-                                mockSettingsImpl.addListeners(
+                                mockSettingsImpl.addListener(
                                         new Object[] {}, new LinkedList<Object>(), "myListeners"))
                 .hasMessageContaining("myListeners() requires at least one listener");
 
         assertThatThrownBy(
                         () ->
-                                mockSettingsImpl.addListeners(
+                                mockSettingsImpl.addListener(
                                         null, new LinkedList<Object>(), "myListeners"))
                 .hasMessageContaining("myListeners() does not accept null vararg array");
 
         assertThatThrownBy(
                         () ->
-                                mockSettingsImpl.addListeners(
+                                mockSettingsImpl.addListener(
                                         new Object[] {null},
                                         new LinkedList<Object>(),
                                         "myListeners"))
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/AbstractByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/AbstractByteBuddyMockMakerTest.java
index 93c8913ac..bb4e44a83 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/AbstractByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/AbstractByteBuddyMockMakerTest.java
@@ -16,7 +16,7 @@ import org.mockito.Mockito;
 import org.mockito.internal.creation.AbstractMockMakerTest;
 import org.mockito.internal.handler.MockHandlerImpl;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 import org.mockitoutil.ClassLoaders;
@@ -97,7 +97,7 @@ public abstract class AbstractByteBuddyMockMakerTest<MM extends MockMaker>
 
     @Test
     public void should_create_mock_from_class_with_super_call_to_final_method() throws Exception {
-        MockCreationSettings<CallingSuperMethodClass> settings =
+        MockCreationOptions<CallingSuperMethodClass> settings =
                 settingsWithSuperCall(CallingSuperMethodClass.class);
         SampleClass proxy =
                 mockMaker.createMock(
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMakerTest.java
index 1a9eebec8..0eee24837 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/ByteBuddyMockMakerTest.java
@@ -8,7 +8,7 @@ import static org.mockito.Mockito.verify;
 
 import org.junit.Test;
 import org.mockito.Mock;
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.internal.handler.MockHandlerImpl;
 import org.mockitoutil.TestBase;
 
@@ -20,7 +20,7 @@ public class ByteBuddyMockMakerTest extends TestBase {
     public void should_delegate_call() {
         ByteBuddyMockMaker mockMaker = new ByteBuddyMockMaker(delegate);
 
-        CreationSettings<Object> creationSettings = new CreationSettings<Object>();
+        MockCreationSettings<Object> creationSettings = new MockCreationSettings<Object>();
         MockHandlerImpl<Object> handler = new MockHandlerImpl<Object>(creationSettings);
 
         mockMaker.createMockType(creationSettings);
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
index 9069e50b8..93b181100 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineByteBuddyMockMakerTest.java
@@ -6,7 +6,7 @@ package org.mockito.internal.creation.bytebuddy;
 
 import org.junit.Test;
 import org.mockito.Mock;
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.internal.handler.MockHandlerImpl;
 import org.mockitoutil.TestBase;
 
@@ -20,7 +20,7 @@ public class InlineByteBuddyMockMakerTest extends TestBase {
     public void should_delegate_call() {
         InlineByteBuddyMockMaker mockMaker = new InlineByteBuddyMockMaker(delegate);
 
-        CreationSettings<Object> creationSettings = new CreationSettings<Object>();
+        MockCreationSettings<Object> creationSettings = new MockCreationSettings<Object>();
         MockHandlerImpl<Object> handler = new MockHandlerImpl<Object>(creationSettings);
 
         mockMaker.createMockType(creationSettings);
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMakerTest.java
index dc341d895..46537b032 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/InlineDelegateByteBuddyMockMakerTest.java
@@ -24,13 +24,13 @@ import net.bytebuddy.utility.JavaConstant;
 import org.junit.Test;
 import org.mockito.Answers;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.creation.bytebuddy.sample.DifferentPackage;
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.internal.handler.MockHandlerImpl;
 import org.mockito.internal.stubbing.answers.Returns;
 import org.mockito.internal.util.collections.Sets;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
 
@@ -48,7 +48,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_final_class() throws Exception {
-        MockCreationSettings<FinalClass> settings = settingsFor(FinalClass.class);
+        MockCreationOptions<FinalClass> settings = settingsFor(FinalClass.class);
         FinalClass proxy =
                 mockMaker.createMock(settings, new MockHandlerImpl<FinalClass>(settings));
         assertThat(proxy.foo()).isEqualTo("bar");
@@ -56,7 +56,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_final_spy() throws Exception {
-        MockCreationSettings<FinalSpy> settings = settingsFor(FinalSpy.class);
+        MockCreationOptions<FinalSpy> settings = settingsFor(FinalSpy.class);
         Optional<FinalSpy> proxy =
                 mockMaker.createSpy(
                         settings,
@@ -79,7 +79,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_accessible_inner_spy() throws Exception {
-        MockCreationSettings<Outer.Inner> settings = settingsFor(Outer.Inner.class);
+        MockCreationOptions<Outer.Inner> settings = settingsFor(Outer.Inner.class);
         Optional<Outer.Inner> proxy =
                 mockMaker.createSpy(
                         settings,
@@ -95,7 +95,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_visible_inner_spy() throws Exception {
-        MockCreationSettings<DifferentPackage> settings = settingsFor(DifferentPackage.class);
+        MockCreationOptions<DifferentPackage> settings = settingsFor(DifferentPackage.class);
         Optional<DifferentPackage> proxy =
                 mockMaker.createSpy(
                         settings,
@@ -111,7 +111,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_non_constructable_class() throws Exception {
-        MockCreationSettings<NonConstructableClass> settings =
+        MockCreationOptions<NonConstructableClass> settings =
                 settingsFor(NonConstructableClass.class);
         NonConstructableClass proxy =
                 mockMaker.createMock(
@@ -121,14 +121,14 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_final_class_in_the_JDK() throws Exception {
-        MockCreationSettings<Pattern> settings = settingsFor(Pattern.class);
+        MockCreationOptions<Pattern> settings = settingsFor(Pattern.class);
         Pattern proxy = mockMaker.createMock(settings, new MockHandlerImpl<Pattern>(settings));
         assertThat(proxy.pattern()).isEqualTo("bar");
     }
 
     @Test
     public void should_create_mock_from_abstract_class_with_final_method() throws Exception {
-        MockCreationSettings<FinalMethodAbstractType> settings =
+        MockCreationOptions<FinalMethodAbstractType> settings =
                 settingsFor(FinalMethodAbstractType.class);
         FinalMethodAbstractType proxy =
                 mockMaker.createMock(
@@ -139,7 +139,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_final_class_with_interface_methods() throws Exception {
-        MockCreationSettings<FinalMethod> settings =
+        MockCreationOptions<FinalMethod> settings =
                 settingsFor(FinalMethod.class, SampleInterface.class);
         FinalMethod proxy =
                 mockMaker.createMock(settings, new MockHandlerImpl<FinalMethod>(settings));
@@ -149,7 +149,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_detect_non_overridden_generic_method_of_supertype() throws Exception {
-        MockCreationSettings<GenericSubClass> settings = settingsFor(GenericSubClass.class);
+        MockCreationOptions<GenericSubClass> settings = settingsFor(GenericSubClass.class);
         GenericSubClass proxy =
                 mockMaker.createMock(settings, new MockHandlerImpl<GenericSubClass>(settings));
         assertThat(proxy.value()).isEqualTo("bar");
@@ -157,7 +157,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_hashmap() throws Exception {
-        MockCreationSettings<HashMap> settings = settingsFor(HashMap.class);
+        MockCreationOptions<HashMap> settings = settingsFor(HashMap.class);
         HashMap proxy = mockMaker.createMock(settings, new MockHandlerImpl<HashMap>(settings));
         assertThat(proxy.get(null)).isEqualTo("bar");
     }
@@ -165,7 +165,7 @@ public class InlineDelegateByteBuddyMockMakerTest
     @Test
     @SuppressWarnings("unchecked")
     public void should_throw_exception_redefining_unmodifiable_class() {
-        MockCreationSettings settings = settingsFor(int.class);
+        MockCreationOptions settings = settingsFor(int.class);
         try {
             mockMaker.createMock(settings, new MockHandlerImpl(settings));
             fail("Expected a MockitoException");
@@ -179,7 +179,7 @@ public class InlineDelegateByteBuddyMockMakerTest
     @SuppressWarnings("unchecked")
     public void should_throw_exception_redefining_array() {
         int[] array = new int[5];
-        MockCreationSettings<? extends int[]> settings = settingsFor(array.getClass());
+        MockCreationOptions<? extends int[]> settings = settingsFor(array.getClass());
         try {
             mockMaker.createMock(settings, new MockHandlerImpl(settings));
             fail("Expected a MockitoException");
@@ -190,7 +190,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_create_mock_from_enum() throws Exception {
-        MockCreationSettings<EnumClass> settings = settingsFor(EnumClass.class);
+        MockCreationOptions<EnumClass> settings = settingsFor(EnumClass.class);
         EnumClass proxy = mockMaker.createMock(settings, new MockHandlerImpl<EnumClass>(settings));
         assertThat(proxy.foo()).isEqualTo("bar");
     }
@@ -198,8 +198,8 @@ public class InlineDelegateByteBuddyMockMakerTest
     @Test
     public void should_fail_at_creating_a_mock_of_a_final_class_with_explicit_serialization()
             throws Exception {
-        MockCreationSettings<FinalClass> settings =
-                new CreationSettings<FinalClass>()
+        MockCreationOptions<FinalClass> settings =
+                new MockCreationSettings<FinalClass>()
                         .setTypeToMock(FinalClass.class)
                         .setSerializableMode(SerializableMode.BASIC);
 
@@ -217,8 +217,8 @@ public class InlineDelegateByteBuddyMockMakerTest
     @Test
     public void should_fail_at_creating_a_mock_of_a_final_class_with_extra_interfaces()
             throws Exception {
-        MockCreationSettings<FinalClass> settings =
-                new CreationSettings<FinalClass>()
+        MockCreationOptions<FinalClass> settings =
+                new MockCreationSettings<FinalClass>()
                         .setTypeToMock(FinalClass.class)
                         .setExtraInterfaces(Sets.<Class<?>>newSet(List.class));
 
@@ -235,7 +235,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_mock_interface() {
-        MockSettingsImpl<Set> mockSettings = new MockSettingsImpl<Set>();
+        DefaultMockSettings<Set> mockSettings = new DefaultMockSettings<Set>();
         mockSettings.setTypeToMock(Set.class);
         mockSettings.defaultAnswer(new Returns(10));
         Set<?> proxy = mockMaker.createMock(mockSettings, new MockHandlerImpl<Set>(mockSettings));
@@ -245,7 +245,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_mock_interface_to_string() {
-        MockSettingsImpl<Set> mockSettings = new MockSettingsImpl<Set>();
+        DefaultMockSettings<Set> mockSettings = new DefaultMockSettings<Set>();
         mockSettings.setTypeToMock(Set.class);
         mockSettings.defaultAnswer(new Returns("foo"));
         Set<?> proxy = mockMaker.createMock(mockSettings, new MockHandlerImpl<Set>(mockSettings));
@@ -258,7 +258,7 @@ public class InlineDelegateByteBuddyMockMakerTest
      */
     @Test
     public void should_mock_class_to_string() {
-        MockSettingsImpl<Object> mockSettings = new MockSettingsImpl<Object>();
+        DefaultMockSettings<Object> mockSettings = new DefaultMockSettings<Object>();
         mockSettings.setTypeToMock(Object.class);
         mockSettings.defaultAnswer(new Returns("foo"));
         Object proxy =
@@ -269,7 +269,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_leave_causing_stack() throws Exception {
-        MockSettingsImpl<ExceptionThrowingClass> settings = new MockSettingsImpl<>();
+        DefaultMockSettings<ExceptionThrowingClass> settings = new DefaultMockSettings<>();
         settings.setTypeToMock(ExceptionThrowingClass.class);
         settings.defaultAnswer(Answers.CALLS_REAL_METHODS);
 
@@ -298,7 +298,7 @@ public class InlineDelegateByteBuddyMockMakerTest
     @Test
     public void should_leave_causing_stack_with_two_spies() throws Exception {
         // given
-        MockSettingsImpl<ExceptionThrowingClass> settingsEx = new MockSettingsImpl<>();
+        DefaultMockSettings<ExceptionThrowingClass> settingsEx = new DefaultMockSettings<>();
         settingsEx.setTypeToMock(ExceptionThrowingClass.class);
         settingsEx.defaultAnswer(Answers.CALLS_REAL_METHODS);
         Optional<ExceptionThrowingClass> proxyEx =
@@ -307,7 +307,7 @@ public class InlineDelegateByteBuddyMockMakerTest
                         new MockHandlerImpl<>(settingsEx),
                         new ExceptionThrowingClass());
 
-        MockSettingsImpl<WrapperClass> settingsWr = new MockSettingsImpl<>();
+        DefaultMockSettings<WrapperClass> settingsWr = new DefaultMockSettings<>();
         settingsWr.setTypeToMock(WrapperClass.class);
         settingsWr.defaultAnswer(Answers.CALLS_REAL_METHODS);
         Optional<WrapperClass> proxyWr =
@@ -380,7 +380,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void should_mock_method_of_package_private_class() throws Exception {
-        MockCreationSettings<NonPackagePrivateSubClass> settings =
+        MockCreationOptions<NonPackagePrivateSubClass> settings =
                 settingsFor(NonPackagePrivateSubClass.class);
         NonPackagePrivateSubClass proxy =
                 mockMaker.createMock(
@@ -449,7 +449,7 @@ public class InlineDelegateByteBuddyMockMakerTest
                         .load(null)
                         .getLoaded();
 
-        MockCreationSettings<?> settings = settingsFor(typeWithParameters);
+        MockCreationOptions<?> settings = settingsFor(typeWithParameters);
         @SuppressWarnings("unchecked")
         Object proxy = mockMaker.createMock(settings, new MockHandlerImpl(settings));
 
@@ -476,7 +476,7 @@ public class InlineDelegateByteBuddyMockMakerTest
                         .load(null)
                         .getLoaded();
 
-        MockCreationSettings<?> settings = settingsFor(typeWithCondy);
+        MockCreationOptions<?> settings = settingsFor(typeWithCondy);
         @SuppressWarnings("unchecked")
         Object proxy = mockMaker.createMock(settings, new MockHandlerImpl(settings));
 
@@ -485,7 +485,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void test_clear_mock_clears_handler() {
-        MockCreationSettings<GenericSubClass> settings = settingsFor(GenericSubClass.class);
+        MockCreationOptions<GenericSubClass> settings = settingsFor(GenericSubClass.class);
         GenericSubClass proxy =
                 mockMaker.createMock(settings, new MockHandlerImpl<GenericSubClass>(settings));
         assertThat(mockMaker.getHandler(proxy)).isNotNull();
@@ -499,7 +499,7 @@ public class InlineDelegateByteBuddyMockMakerTest
 
     @Test
     public void test_clear_all_mock_clears_handler() {
-        MockCreationSettings<GenericSubClass> settings = settingsFor(GenericSubClass.class);
+        MockCreationOptions<GenericSubClass> settings = settingsFor(GenericSubClass.class);
         GenericSubClass proxy1 =
                 mockMaker.createMock(settings, new MockHandlerImpl<GenericSubClass>(settings));
         assertThat(mockMaker.getHandler(proxy1)).isNotNull();
@@ -517,9 +517,9 @@ public class InlineDelegateByteBuddyMockMakerTest
         assertThat(mockMaker.getHandler(proxy2)).isNull();
     }
 
-    protected static <T> MockCreationSettings<T> settingsFor(
+    protected static <T> MockCreationOptions<T> settingsFor(
             Class<T> type, Class<?>... extraInterfaces) {
-        MockSettingsImpl<T> mockSettings = new MockSettingsImpl<T>();
+        DefaultMockSettings<T> mockSettings = new DefaultMockSettings<T>();
         mockSettings.setTypeToMock(type);
         mockSettings.defaultAnswer(new Returns("bar"));
         if (extraInterfaces.length > 0) mockSettings.extraInterfaces(extraInterfaces);
diff --git a/src/test/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMakerTest.java b/src/test/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMakerTest.java
index e6a0086c9..87dbdd363 100644
--- a/src/test/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMakerTest.java
+++ b/src/test/java/org/mockito/internal/creation/bytebuddy/SubclassByteBuddyMockMakerTest.java
@@ -9,7 +9,7 @@ import net.bytebuddy.ClassFileVersion;
 import net.bytebuddy.description.modifier.TypeManifestation;
 import net.bytebuddy.dynamic.DynamicType;
 import org.junit.Test;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.plugins.MockMaker;
 
 import java.io.Serializable;
@@ -81,7 +81,7 @@ public class SubclassByteBuddyMockMakerTest
 
     @Test
     public void mock_class_with_annotations() throws Exception {
-        MockSettingsImpl<ClassWithAnnotation> mockSettings = new MockSettingsImpl<>();
+        DefaultMockSettings<ClassWithAnnotation> mockSettings = new DefaultMockSettings<>();
         mockSettings.setTypeToMock(ClassWithAnnotation.class);
 
         ClassWithAnnotation proxy = mockMaker.createMock(mockSettings, dummyHandler());
@@ -104,7 +104,7 @@ public class SubclassByteBuddyMockMakerTest
 
     @Test
     public void mock_class_with_annotations_with_additional_interface() throws Exception {
-        MockSettingsImpl<ClassWithAnnotation> mockSettings = new MockSettingsImpl<>();
+        DefaultMockSettings<ClassWithAnnotation> mockSettings = new DefaultMockSettings<>();
         mockSettings.setTypeToMock(ClassWithAnnotation.class);
         mockSettings.extraInterfaces(Serializable.class);
 
@@ -128,7 +128,7 @@ public class SubclassByteBuddyMockMakerTest
 
     @Test
     public void mock_interface_with_annotations() throws Exception {
-        MockSettingsImpl<InterfaceWithAnnotation> mockSettings = new MockSettingsImpl<>();
+        DefaultMockSettings<InterfaceWithAnnotation> mockSettings = new DefaultMockSettings<>();
         mockSettings.setTypeToMock(InterfaceWithAnnotation.class);
 
         InterfaceWithAnnotation proxy = mockMaker.createMock(mockSettings, dummyHandler());
@@ -151,7 +151,7 @@ public class SubclassByteBuddyMockMakerTest
 
     @Test
     public void mock_interface_with_annotations_with_additional_interface() throws Exception {
-        MockSettingsImpl<InterfaceWithAnnotation> mockSettings = new MockSettingsImpl<>();
+        DefaultMockSettings<InterfaceWithAnnotation> mockSettings = new DefaultMockSettings<>();
         mockSettings.setTypeToMock(InterfaceWithAnnotation.class);
         mockSettings.extraInterfaces(Serializable.class);
 
@@ -174,7 +174,7 @@ public class SubclassByteBuddyMockMakerTest
 
     @Test
     public void mock_type_without_annotations() throws Exception {
-        MockSettingsImpl<ClassWithAnnotation> mockSettings = new MockSettingsImpl<>();
+        DefaultMockSettings<ClassWithAnnotation> mockSettings = new DefaultMockSettings<>();
         mockSettings.setTypeToMock(ClassWithAnnotation.class);
         mockSettings.withoutAnnotations();
 
diff --git a/src/test/java/org/mockito/internal/framework/DefaultMockitoFrameworkTest.java b/src/test/java/org/mockito/internal/framework/DefaultMockitoFrameworkTest.java
index 3b2884e52..c97a86c6a 100644
--- a/src/test/java/org/mockito/internal/framework/DefaultMockitoFrameworkTest.java
+++ b/src/test/java/org/mockito/internal/framework/DefaultMockitoFrameworkTest.java
@@ -26,10 +26,10 @@ import org.mockito.ArgumentMatchers;
 import org.mockito.MockSettings;
 import org.mockito.StateMaster;
 import org.mockito.exceptions.misusing.RedundantListenerException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.listeners.MockCreationListener;
 import org.mockito.listeners.MockitoListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.InlineMockMaker;
 import org.mockitoutil.TestBase;
 
@@ -92,8 +92,8 @@ public class DefaultMockitoFrameworkTest extends TestBase {
         Set mock2 = mock(Set.class);
 
         // then
-        verify(listener).onMockCreated(eq(mock), any(MockCreationSettings.class));
-        verify(listener).onMockCreated(eq(mock2), any(MockCreationSettings.class));
+        verify(listener).onMockCreated(eq(mock), any(MockCreationOptions.class));
+        verify(listener).onMockCreated(eq(mock2), any(MockCreationOptions.class));
         verifyNoMoreInteractions(listener);
     }
 
@@ -106,7 +106,7 @@ public class DefaultMockitoFrameworkTest extends TestBase {
 
         // and hooked up correctly
         mock(List.class);
-        verify(listener).onMockCreated(ArgumentMatchers.any(), any(MockCreationSettings.class));
+        verify(listener).onMockCreated(ArgumentMatchers.any(), any(MockCreationOptions.class));
 
         // when
         framework.removeListener(listener);
@@ -151,7 +151,7 @@ public class DefaultMockitoFrameworkTest extends TestBase {
     @Test
     public void clears_all_mocks() {
         // clearing mocks only works with inline mocking
-        assumeTrue(Plugins.getMockMaker() instanceof InlineMockMaker);
+        assumeTrue(PluginRegistry.getMockMaker() instanceof InlineMockMaker);
 
         // given
         List list1 = mock(List.class);
@@ -170,7 +170,7 @@ public class DefaultMockitoFrameworkTest extends TestBase {
     @Test
     public void clears_mock() {
         // clearing mocks only works with inline mocking
-        assumeTrue(Plugins.getMockMaker() instanceof InlineMockMaker);
+        assumeTrue(PluginRegistry.getMockMaker() instanceof InlineMockMaker);
 
         // given
         List list1 = mock(List.class);
diff --git a/src/test/java/org/mockito/internal/handler/InvocationNotifierHandlerTest.java b/src/test/java/org/mockito/internal/handler/InvocationNotifierHandlerTest.java
index 54e8394c0..326bd0b62 100644
--- a/src/test/java/org/mockito/internal/handler/InvocationNotifierHandlerTest.java
+++ b/src/test/java/org/mockito/internal/handler/InvocationNotifierHandlerTest.java
@@ -22,12 +22,12 @@ import org.junit.runner.RunWith;
 import org.mockito.Mock;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.invocation.Invocation;
 import org.mockito.junit.MockitoJUnitRunner;
 import org.mockito.listeners.InvocationListener;
 import org.mockito.listeners.MethodInvocationReport;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.stubbing.Answer;
 
 @RunWith(MockitoJUnitRunner.class)
@@ -52,8 +52,8 @@ public class InvocationNotifierHandlerTest {
         notifier =
                 new InvocationNotifierHandler<>(
                         mockHandler,
-                        (MockCreationSettings<ArrayList<Answer<?>>>)
-                                new MockSettingsImpl<ArrayList<Answer<?>>>()
+                        (MockCreationOptions<ArrayList<Answer<?>>>)
+                                new DefaultMockSettings<ArrayList<Answer<?>>>()
                                         .invocationListeners(customListener, listener1, listener2));
     }
 
diff --git a/src/test/java/org/mockito/internal/handler/MockHandlerFactoryTest.java b/src/test/java/org/mockito/internal/handler/MockHandlerFactoryTest.java
index d82bc7829..4062abf94 100644
--- a/src/test/java/org/mockito/internal/handler/MockHandlerFactoryTest.java
+++ b/src/test/java/org/mockito/internal/handler/MockHandlerFactoryTest.java
@@ -10,11 +10,11 @@ import static org.mockito.internal.handler.MockHandlerFactory.createMockHandler;
 
 import org.junit.Test;
 import org.mockito.Mockito;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.stubbing.answers.Returns;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockitousage.IMethods;
 import org.mockitoutil.TestBase;
 
@@ -29,8 +29,8 @@ public class MockHandlerFactoryTest extends TestBase {
     // see issue 331
     public void handle_result_must_not_be_null_for_primitives() throws Throwable {
         // given:
-        MockCreationSettings<?> settings =
-                (MockCreationSettings<?>) new MockSettingsImpl().defaultAnswer(new Returns(null));
+        MockCreationOptions<?> settings =
+                (MockCreationOptions<?>) new DefaultMockSettings().defaultAnswer(new Returns(null));
         MockHandler<?> handler = createMockHandler(settings);
 
         mock.intReturningMethod();
@@ -48,8 +48,8 @@ public class MockHandlerFactoryTest extends TestBase {
     // see issue 331
     public void valid_handle_result_is_permitted() throws Throwable {
         // given:
-        MockCreationSettings<?> settings =
-                (MockCreationSettings<?>) new MockSettingsImpl().defaultAnswer(new Returns(123));
+        MockCreationOptions<?> settings =
+                (MockCreationOptions<?>) new DefaultMockSettings().defaultAnswer(new Returns(123));
         MockHandler<?> handler = createMockHandler(settings);
 
         mock.intReturningMethod();
diff --git a/src/test/java/org/mockito/internal/handler/MockHandlerImplTest.java b/src/test/java/org/mockito/internal/handler/MockHandlerImplTest.java
index a0169c25f..93cc65cae 100644
--- a/src/test/java/org/mockito/internal/handler/MockHandlerImplTest.java
+++ b/src/test/java/org/mockito/internal/handler/MockHandlerImplTest.java
@@ -17,7 +17,7 @@ import org.junit.Test;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.misusing.InvalidUseOfMatchersException;
 import org.mockito.exceptions.misusing.WrongTypeOfReturnValue;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.invocation.InvocationBuilder;
 import org.mockito.internal.invocation.InvocationMatcher;
 import org.mockito.internal.invocation.MatchersBinder;
@@ -37,7 +37,7 @@ public class MockHandlerImplTest extends TestBase {
         // given
         Invocation invocation = new InvocationBuilder().toInvocation();
         @SuppressWarnings("rawtypes")
-        MockHandlerImpl<?> handler = new MockHandlerImpl(new MockSettingsImpl());
+        MockHandlerImpl<?> handler = new MockHandlerImpl(new DefaultMockSettings());
         mockingProgress().verificationStarted(VerificationModeFactory.atLeastOnce());
         handler.matchersBinder =
                 new MatchersBinder() {
@@ -79,7 +79,7 @@ public class MockHandlerImplTest extends TestBase {
     @Test
     public void should_report_bogus_default_answer() throws Throwable {
         // given
-        MockSettingsImpl mockSettings = mock(MockSettingsImpl.class);
+        DefaultMockSettings mockSettings = mock(DefaultMockSettings.class);
         MockHandlerImpl<?> handler = new MockHandlerImpl(mockSettings);
         given(mockSettings.getDefaultAnswer()).willReturn(new Returns(AWrongType.WRONG_TYPE));
         Invocation invocation =
diff --git a/src/test/java/org/mockito/internal/listeners/StubbingLookupNotifierTest.java b/src/test/java/org/mockito/internal/listeners/StubbingLookupNotifierTest.java
index 6b2c77c69..77dbfc262 100644
--- a/src/test/java/org/mockito/internal/listeners/StubbingLookupNotifierTest.java
+++ b/src/test/java/org/mockito/internal/listeners/StubbingLookupNotifierTest.java
@@ -17,7 +17,7 @@ import java.util.List;
 import org.assertj.core.util.Lists;
 import org.junit.Test;
 import org.mockito.ArgumentMatcher;
-import org.mockito.internal.creation.settings.CreationSettings;
+import org.mockito.internal.creation.settings.MockCreationSettings;
 import org.mockito.invocation.Invocation;
 import org.mockito.listeners.StubbingLookupListener;
 import org.mockito.stubbing.Stubbing;
@@ -28,7 +28,7 @@ public class StubbingLookupNotifierTest extends TestBase {
     Invocation invocation = mock(Invocation.class);
     Stubbing stubbingFound = mock(Stubbing.class);
     Collection<Stubbing> allStubbings = mock(Collection.class);
-    CreationSettings creationSettings = mock(CreationSettings.class);
+    MockCreationSettings creationSettings = mock(MockCreationSettings.class);
 
     @Test
     public void does_not_do_anything_when_list_is_empty() {
diff --git a/src/test/java/org/mockito/internal/runners/DefaultInternalRunnerTest.java b/src/test/java/org/mockito/internal/runners/DefaultInternalRunnerTest.java
index 0e4e40076..769d5d30a 100644
--- a/src/test/java/org/mockito/internal/runners/DefaultInternalRunnerTest.java
+++ b/src/test/java/org/mockito/internal/runners/DefaultInternalRunnerTest.java
@@ -21,7 +21,7 @@ import org.junit.runner.notification.RunListener;
 import org.junit.runner.notification.RunNotifier;
 import org.junit.runners.model.Statement;
 import org.mockito.Mock;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.junit.MockitoTestListener;
 import org.mockito.internal.junit.TestFinishedEvent;
 import org.mockito.internal.util.Supplier;
@@ -48,7 +48,7 @@ public class DefaultInternalRunnerTest {
     @Test
     public void does_not_fail_second_test_when_first_test_fail() throws Exception {
         // The TestFailOnInitialization is initialized properly by inline mock maker
-        Assume.assumeThat(Plugins.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
 
         new DefaultInternalRunner(TestFailOnInitialization.class, supplier)
                 .run(newNotifier(runListener));
diff --git a/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplStubbingTest.java b/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplStubbingTest.java
index fafff6588..4cc1105de 100644
--- a/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplStubbingTest.java
+++ b/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplStubbingTest.java
@@ -11,7 +11,7 @@ import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingPro
 import org.junit.Before;
 import org.junit.Test;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.invocation.InvocationBuilder;
 import org.mockito.internal.invocation.InvocationMatcher;
 import org.mockito.internal.progress.MockingProgress;
@@ -31,12 +31,12 @@ public class InvocationContainerImplStubbingTest extends TestBase {
     public void setup() {
         state = mockingProgress();
 
-        invocationContainerImpl = new InvocationContainerImpl(new MockSettingsImpl());
+        invocationContainerImpl = new InvocationContainerImpl(new DefaultMockSettings());
         invocationContainerImpl.setInvocationForPotentialStubbing(
                 new InvocationBuilder().toInvocationMatcher());
 
         invocationContainerImplStubOnly =
-                new InvocationContainerImpl(new MockSettingsImpl().stubOnly());
+                new InvocationContainerImpl(new DefaultMockSettings().stubOnly());
         invocationContainerImplStubOnly.setInvocationForPotentialStubbing(
                 new InvocationBuilder().toInvocationMatcher());
 
diff --git a/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplTest.java b/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplTest.java
index aef75eea4..a677ac641 100644
--- a/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplTest.java
+++ b/src/test/java/org/mockito/internal/stubbing/InvocationContainerImplTest.java
@@ -12,22 +12,22 @@ import java.util.LinkedList;
 import java.util.concurrent.CountDownLatch;
 
 import org.junit.Test;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.invocation.InvocationBuilder;
 import org.mockito.internal.invocation.InvocationMatcher;
 import org.mockito.internal.stubbing.answers.Returns;
 import org.mockito.internal.stubbing.defaultanswers.ReturnsEmptyValues;
 import org.mockito.invocation.Invocation;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 /**
  * Author: Szczepan Faber
  */
 public class InvocationContainerImplTest {
 
-    InvocationContainerImpl container = new InvocationContainerImpl(new MockSettingsImpl());
+    InvocationContainerImpl container = new InvocationContainerImpl(new DefaultMockSettings());
     InvocationContainerImpl containerStubOnly =
-            new InvocationContainerImpl((MockCreationSettings) new MockSettingsImpl().stubOnly());
+            new InvocationContainerImpl((MockCreationOptions) new DefaultMockSettings().stubOnly());
     Invocation invocation = new InvocationBuilder().toInvocation();
     LinkedList<Throwable> exceptions = new LinkedList<Throwable>();
 
diff --git a/src/test/java/org/mockito/internal/stubbing/answers/CallsRealMethodsTest.java b/src/test/java/org/mockito/internal/stubbing/answers/CallsRealMethodsTest.java
index f8d904f2b..c7c381217 100644
--- a/src/test/java/org/mockito/internal/stubbing/answers/CallsRealMethodsTest.java
+++ b/src/test/java/org/mockito/internal/stubbing/answers/CallsRealMethodsTest.java
@@ -13,7 +13,7 @@ import java.util.ArrayList;
 import org.assertj.core.api.Assertions;
 import org.junit.Test;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.MockitoCore;
+import org.mockito.internal.MockitoEngine;
 import org.mockito.internal.invocation.InvocationBuilder;
 import org.mockito.invocation.Invocation;
 
@@ -46,7 +46,7 @@ public class CallsRealMethodsTest {
         // given
         ArrayList<?> mock = mock(ArrayList.class);
         mock.clear();
-        Invocation invocationOnClass = new MockitoCore().getLastInvocation();
+        Invocation invocationOnClass = new MockitoEngine().getLastInvocation();
         // when
         new CallsRealMethods().validateFor(invocationOnClass);
         // then no exception is thrown
diff --git a/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java b/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
index 3691412e5..cb5a5a20a 100755
--- a/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
+++ b/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
@@ -9,7 +9,7 @@ import static org.junit.Assume.assumeFalse;
 import static org.mockito.Mockito.when;
 
 import org.junit.Test;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.stubbing.defaultanswers.ReturnsGenericDeepStubsTest.WithGenerics;
 import org.mockito.internal.util.MockUtil;
 import org.mockitoutil.TestBase;
@@ -58,7 +58,7 @@ public class ReturnsMocksTest extends TestBase {
 
     @Test
     public void should_return_null_for_final_class_if_unsupported() throws Throwable {
-        assumeFalse(Plugins.getMockMaker().isTypeMockable(Baz.class).mockable());
+        assumeFalse(PluginRegistry.getMockMaker().isTypeMockable(Baz.class).mockable());
         assertNull(values.answer(invocationOf(AllInterface.class, "getFinalClass")));
     }
 
diff --git a/src/test/java/org/mockito/internal/util/MockNameImplTest.java b/src/test/java/org/mockito/internal/util/MockNameImplTest.java
index 583bd7ac0..0d2353118 100644
--- a/src/test/java/org/mockito/internal/util/MockNameImplTest.java
+++ b/src/test/java/org/mockito/internal/util/MockNameImplTest.java
@@ -14,7 +14,7 @@ public class MockNameImplTest extends TestBase {
     @Test
     public void shouldProvideTheNameForClass() throws Exception {
         // when
-        String name = new MockNameImpl(null, SomeClass.class, false).toString();
+        String name = new MockNameImplementation(null, SomeClass.class, false).toString();
         // then
         assertEquals("someClass", name);
     }
@@ -22,7 +22,7 @@ public class MockNameImplTest extends TestBase {
     @Test
     public void shouldProvideTheNameForClassOnStaticMock() throws Exception {
         // when
-        String name = new MockNameImpl(null, SomeClass.class, true).toString();
+        String name = new MockNameImplementation(null, SomeClass.class, true).toString();
         // then
         assertEquals("SomeClass.class", name);
     }
@@ -32,7 +32,7 @@ public class MockNameImplTest extends TestBase {
         // given
         SomeInterface anonymousInstance = new SomeInterface() {};
         // when
-        String name = new MockNameImpl(null, anonymousInstance.getClass(), false).toString();
+        String name = new MockNameImplementation(null, anonymousInstance.getClass(), false).toString();
         // then
         assertEquals("someInterface", name);
     }
@@ -42,7 +42,7 @@ public class MockNameImplTest extends TestBase {
         // given
         SomeInterface anonymousInstance = new SomeInterface() {};
         // when
-        String name = new MockNameImpl(null, anonymousInstance.getClass(), true).toString();
+        String name = new MockNameImplementation(null, anonymousInstance.getClass(), true).toString();
         // then
         assertEquals("SomeInterface$.class", name);
     }
@@ -50,7 +50,7 @@ public class MockNameImplTest extends TestBase {
     @Test
     public void shouldProvideTheGivenName() throws Exception {
         // when
-        String name = new MockNameImpl("The Hulk", SomeClass.class, false).toString();
+        String name = new MockNameImplementation("The Hulk", SomeClass.class, false).toString();
         // then
         assertEquals("The Hulk", name);
     }
@@ -58,7 +58,7 @@ public class MockNameImplTest extends TestBase {
     @Test
     public void shouldProvideTheGivenNameOnStatic() throws Exception {
         // when
-        String name = new MockNameImpl("The Hulk", SomeClass.class, true).toString();
+        String name = new MockNameImplementation("The Hulk", SomeClass.class, true).toString();
         // then
         assertEquals("The Hulk", name);
     }
diff --git a/src/test/java/org/mockito/internal/util/MockSettingsTest.java b/src/test/java/org/mockito/internal/util/MockSettingsTest.java
index ab39828b1..411d31341 100644
--- a/src/test/java/org/mockito/internal/util/MockSettingsTest.java
+++ b/src/test/java/org/mockito/internal/util/MockSettingsTest.java
@@ -11,15 +11,15 @@ import java.util.List;
 
 import org.junit.Test;
 import org.mockito.Mockito;
-import org.mockito.internal.creation.settings.CreationSettings;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.internal.creation.settings.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockitoutil.TestBase;
 
 public class MockSettingsTest extends TestBase {
     @Test
     public void public_api_for_creating_settings() throws Exception {
         // when
-        MockCreationSettings<List> settings =
+        MockCreationOptions<List> settings =
                 Mockito.withSettings().name("dummy").build(List.class);
 
         // then
@@ -29,10 +29,10 @@ public class MockSettingsTest extends TestBase {
 
     @Test
     public void test_without_annotations() throws Exception {
-        MockCreationSettings<List> settings =
+        MockCreationOptions<List> settings =
                 Mockito.withSettings().withoutAnnotations().build(List.class);
 
-        CreationSettings copy = new CreationSettings((CreationSettings) settings);
+        MockCreationSettings copy = new MockCreationSettings((MockCreationSettings) settings);
 
         assertEquals(List.class, settings.getTypeToMock());
         assertEquals(List.class, copy.getTypeToMock());
diff --git a/src/test/java/org/mockito/internal/util/MockUtilTest.java b/src/test/java/org/mockito/internal/util/MockUtilTest.java
index 834178cde..d102b6d39 100644
--- a/src/test/java/org/mockito/internal/util/MockUtilTest.java
+++ b/src/test/java/org/mockito/internal/util/MockUtilTest.java
@@ -17,7 +17,7 @@ import org.assertj.core.api.Assertions;
 import org.junit.Test;
 import org.mockito.Mockito;
 import org.mockito.exceptions.misusing.NotAMockException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockitoutil.TestBase;
 
 @SuppressWarnings("unchecked")
@@ -101,7 +101,7 @@ public class MockUtilTest extends TestBase {
     @Test
     public void should_know_if_type_is_mockable() throws Exception {
         Assertions.assertThat(MockUtil.typeMockabilityOf(FinalClass.class, null).mockable())
-                .isEqualTo(Plugins.getMockMaker().isTypeMockable(FinalClass.class).mockable());
+                .isEqualTo(PluginRegistry.getMockMaker().isTypeMockable(FinalClass.class).mockable());
 
         assertFalse(MockUtil.typeMockabilityOf(int.class, null).mockable());
 
diff --git a/src/test/java/org/mockito/internal/verification/NoInteractionsTest.java b/src/test/java/org/mockito/internal/verification/NoInteractionsTest.java
index 7c628cd8e..cd274b7de 100644
--- a/src/test/java/org/mockito/internal/verification/NoInteractionsTest.java
+++ b/src/test/java/org/mockito/internal/verification/NoInteractionsTest.java
@@ -10,7 +10,7 @@ import static org.mockito.Mockito.mock;
 import org.assertj.core.api.Assertions;
 import org.junit.Test;
 import org.mockito.exceptions.verification.NoInteractionsWanted;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.invocation.InvocationBuilder;
 import org.mockito.internal.invocation.InvocationMatcher;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
@@ -26,7 +26,7 @@ public class NoInteractionsTest extends TestBase {
         IMethods mock = mock(IMethods.class, "a mock");
         InvocationMatcher i = new InvocationBuilder().mock(mock).toInvocationMatcher();
 
-        InvocationContainerImpl invocations = new InvocationContainerImpl(new MockSettingsImpl());
+        InvocationContainerImpl invocations = new InvocationContainerImpl(new DefaultMockSettings());
         invocations.setInvocationForPotentialStubbing(i);
 
         try {
diff --git a/src/test/java/org/mockito/internal/verification/NoMoreInteractionsTest.java b/src/test/java/org/mockito/internal/verification/NoMoreInteractionsTest.java
index e75898f62..06ed54e2b 100644
--- a/src/test/java/org/mockito/internal/verification/NoMoreInteractionsTest.java
+++ b/src/test/java/org/mockito/internal/verification/NoMoreInteractionsTest.java
@@ -13,7 +13,7 @@ import org.assertj.core.api.Assertions;
 import org.junit.Test;
 import org.mockito.exceptions.verification.NoInteractionsWanted;
 import org.mockito.exceptions.verification.VerificationInOrderFailure;
-import org.mockito.internal.creation.MockSettingsImpl;
+import org.mockito.internal.creation.DefaultMockSettings;
 import org.mockito.internal.invocation.InvocationBuilder;
 import org.mockito.internal.invocation.InvocationMatcher;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
@@ -91,7 +91,7 @@ public class NoMoreInteractionsTest extends TestBase {
         IMethods mock = mock(IMethods.class, "a mock");
         InvocationMatcher i = new InvocationBuilder().mock(mock).toInvocationMatcher();
 
-        InvocationContainerImpl invocations = new InvocationContainerImpl(new MockSettingsImpl());
+        InvocationContainerImpl invocations = new InvocationContainerImpl(new DefaultMockSettings());
         invocations.setInvocationForPotentialStubbing(i);
 
         try {
diff --git a/src/test/java/org/mockitointegration/DeferMockMakersClassLoadingTest.java b/src/test/java/org/mockitointegration/DeferMockMakersClassLoadingTest.java
index 63c0d761b..f34b5ea79 100644
--- a/src/test/java/org/mockitointegration/DeferMockMakersClassLoadingTest.java
+++ b/src/test/java/org/mockitointegration/DeferMockMakersClassLoadingTest.java
@@ -18,7 +18,7 @@ import org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker;
 import org.mockito.internal.creation.bytebuddy.SubclassByteBuddyMockMaker;
 import org.mockito.internal.creation.proxy.ProxyMockMaker;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.MockMaker;
 import org.mockitoutil.ClassLoaders;
 
@@ -64,7 +64,7 @@ public class DeferMockMakersClassLoadingTest {
 
     public static class CustomMockMaker implements MockMaker {
         @Override
-        public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+        public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
             return settings.getTypeToMock().cast(MY_MOCK);
         }
 
@@ -74,7 +74,7 @@ public class DeferMockMakersClassLoadingTest {
         }
 
         @Override
-        public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+        public void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings) {
             throw new UnsupportedOperationException();
         }
 
diff --git a/src/test/java/org/mockitointegration/NoJUnitDependenciesTest.java b/src/test/java/org/mockitointegration/NoJUnitDependenciesTest.java
index 503d85961..a697474fe 100644
--- a/src/test/java/org/mockitointegration/NoJUnitDependenciesTest.java
+++ b/src/test/java/org/mockitointegration/NoJUnitDependenciesTest.java
@@ -14,7 +14,7 @@ import org.hamcrest.Matcher;
 import org.junit.Assume;
 import org.junit.Test;
 import org.mockito.Mockito;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockitoutil.ClassLoaders;
 import org.objenesis.Objenesis;
 
@@ -23,7 +23,7 @@ public class NoJUnitDependenciesTest {
     @Test
     public void pure_mockito_should_not_depend_JUnit___ByteBuddy() throws Exception {
         Assume.assumeTrue(
-                "ByteBuddyMockMaker".equals(Plugins.getMockMaker().getClass().getSimpleName()));
+                "ByteBuddyMockMaker".equals(PluginRegistry.getMockMaker().getClass().getSimpleName()));
 
         ClassLoader classLoader_without_JUnit =
                 ClassLoaders.excludingClassLoader()
diff --git a/src/test/java/org/mockitousage/annotation/SpyAnnotationTest.java b/src/test/java/org/mockitousage/annotation/SpyAnnotationTest.java
index daa71bed3..ce18bc3f2 100644
--- a/src/test/java/org/mockitousage/annotation/SpyAnnotationTest.java
+++ b/src/test/java/org/mockitousage/annotation/SpyAnnotationTest.java
@@ -33,7 +33,7 @@ import org.mockito.Mockito;
 import org.mockito.MockitoAnnotations;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.InlineMockMaker;
 import org.mockitoutil.TestBase;
 
@@ -195,7 +195,7 @@ public class SpyAnnotationTest extends TestBase {
 
     @Test
     public void should_spy_private_inner() throws Exception {
-        Assume.assumeThat(Plugins.getMockMaker(), instanceOf(InlineMockMaker.class));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), instanceOf(InlineMockMaker.class));
 
         WithInnerPrivate inner = new WithInnerPrivate();
         MockitoAnnotations.openMocks(inner);
@@ -206,7 +206,7 @@ public class SpyAnnotationTest extends TestBase {
 
     @Test
     public void should_report_private_inner_not_supported() throws Exception {
-        Assume.assumeThat(Plugins.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
 
         try {
             MockitoAnnotations.openMocks(new WithInnerPrivate());
diff --git a/src/test/java/org/mockitousage/debugging/StubbingLookupListenerCallbackTest.java b/src/test/java/org/mockitousage/debugging/StubbingLookupListenerCallbackTest.java
index aa22e538a..650377f95 100644
--- a/src/test/java/org/mockitousage/debugging/StubbingLookupListenerCallbackTest.java
+++ b/src/test/java/org/mockitousage/debugging/StubbingLookupListenerCallbackTest.java
@@ -18,7 +18,7 @@ import org.mockito.ArgumentMatcher;
 import org.mockito.InOrder;
 import org.mockito.listeners.StubbingLookupEvent;
 import org.mockito.listeners.StubbingLookupListener;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockitousage.IMethods;
 import org.mockitoutil.ConcurrentTesting;
 import org.mockitoutil.TestBase;
@@ -177,7 +177,7 @@ public class StubbingLookupListenerCallbackTest extends TestBase {
     public void add_listeners_concurrently_sanity_check() throws Exception {
         // given
         final IMethods mock = mock(IMethods.class);
-        final MockCreationSettings<?> settings = mockingDetails(mock).getMockCreationSettings();
+        final MockCreationOptions<?> settings = mockingDetails(mock).getMockCreationSettings();
 
         List<Runnable> runnables = new LinkedList<Runnable>();
         for (int i = 0; i < 50; i++) {
diff --git a/src/test/java/org/mockitousage/misuse/InvalidUsageTest.java b/src/test/java/org/mockitousage/misuse/InvalidUsageTest.java
index e4a8275be..f82b0ff58 100644
--- a/src/test/java/org/mockitousage/misuse/InvalidUsageTest.java
+++ b/src/test/java/org/mockitousage/misuse/InvalidUsageTest.java
@@ -21,7 +21,7 @@ import org.mockito.InOrder;
 import org.mockito.Mock;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.misusing.MissingMethodInvocationException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.InlineMockMaker;
 import org.mockitousage.IMethods;
 import org.mockitoutil.TestBase;
@@ -161,7 +161,7 @@ public class InvalidUsageTest extends TestBase {
 
     @Test
     public void shouldNotAllowMockingFinalClassesIfDisabled() {
-        Assume.assumeThat(Plugins.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), not(instanceOf(InlineMockMaker.class)));
 
         assertThatThrownBy(
                         () -> {
@@ -176,7 +176,7 @@ public class InvalidUsageTest extends TestBase {
 
     @Test
     public void shouldAllowMockingFinalClassesIfEnabled() {
-        Assume.assumeThat(Plugins.getMockMaker(), instanceOf(InlineMockMaker.class));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), instanceOf(InlineMockMaker.class));
         assertThat(mock(FinalClass.class)).isInstanceOf(FinalClass.class);
     }
 
diff --git a/src/test/java/org/mockitousage/spies/PartialMockingWithSpiesTest.java b/src/test/java/org/mockitousage/spies/PartialMockingWithSpiesTest.java
index ccd85c2b2..369afda21 100644
--- a/src/test/java/org/mockitousage/spies/PartialMockingWithSpiesTest.java
+++ b/src/test/java/org/mockitousage/spies/PartialMockingWithSpiesTest.java
@@ -20,7 +20,7 @@ import org.assertj.core.api.Assertions;
 import org.junit.Assume;
 import org.junit.Before;
 import org.junit.Test;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker;
 import org.mockito.internal.util.reflection.ReflectionMemberAccessor;
 import org.mockitoutil.TestBase;
@@ -113,7 +113,7 @@ public class PartialMockingWithSpiesTest extends TestBase {
     @Test
     public void shouldStackTraceGetFilteredOnUserExceptions() {
         Assume.assumeThat(
-                Plugins.getMemberAccessor(), not(instanceOf(ReflectionMemberAccessor.class)));
+                PluginRegistry.getMemberAccessor(), not(instanceOf(ReflectionMemberAccessor.class)));
 
         try {
             // when
@@ -132,8 +132,8 @@ public class PartialMockingWithSpiesTest extends TestBase {
 
     @Test
     public void shouldStackTraceGetFilteredOnUserExceptionsReflectionForJavaOfVersionLessThan21() {
-        Assume.assumeThat(Plugins.getMockMaker(), instanceOf(InlineByteBuddyMockMaker.class));
-        Assume.assumeThat(Plugins.getMemberAccessor(), instanceOf(ReflectionMemberAccessor.class));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), instanceOf(InlineByteBuddyMockMaker.class));
+        Assume.assumeThat(PluginRegistry.getMemberAccessor(), instanceOf(ReflectionMemberAccessor.class));
         Assume.assumeTrue(ClassFileVersion.ofThisVm().isLessThan(JAVA_V21));
 
         try {
@@ -157,8 +157,8 @@ public class PartialMockingWithSpiesTest extends TestBase {
 
     @Test
     public void shouldStackTraceGetFilteredOnUserExceptionsReflectionForJava21AndHigher() {
-        Assume.assumeThat(Plugins.getMockMaker(), instanceOf(InlineByteBuddyMockMaker.class));
-        Assume.assumeThat(Plugins.getMemberAccessor(), instanceOf(ReflectionMemberAccessor.class));
+        Assume.assumeThat(PluginRegistry.getMockMaker(), instanceOf(InlineByteBuddyMockMaker.class));
+        Assume.assumeThat(PluginRegistry.getMemberAccessor(), instanceOf(ReflectionMemberAccessor.class));
         Assume.assumeTrue(ClassFileVersion.ofThisVm().isAtLeast(JAVA_V21));
 
         try {
diff --git a/src/test/java/org/mockitoutil/ClassLoaders.java b/src/test/java/org/mockitoutil/ClassLoaders.java
index 308b309ec..0f5d345d9 100644
--- a/src/test/java/org/mockitoutil/ClassLoaders.java
+++ b/src/test/java/org/mockitoutil/ClassLoaders.java
@@ -36,7 +36,7 @@ import java.util.concurrent.Executors;
 import java.util.concurrent.Future;
 import java.util.concurrent.ThreadFactory;
 
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.plugins.MemberAccessor;
 import org.objenesis.Objenesis;
 import org.objenesis.ObjenesisStd;
@@ -169,7 +169,7 @@ public abstract class ClassLoaders {
                         continue;
                     }
                     if (declaredField.getType() == field.getType()) { // don't copy this
-                        MemberAccessor accessor = Plugins.getMemberAccessor();
+                        MemberAccessor accessor = PluginRegistry.getMemberAccessor();
                         accessor.set(declaredField, reloaded, accessor.get(field, task));
                     }
                 }
diff --git a/src/test/java/org/mockitoutil/TestBase.java b/src/test/java/org/mockitoutil/TestBase.java
index 3f772d020..425806557 100644
--- a/src/test/java/org/mockitoutil/TestBase.java
+++ b/src/test/java/org/mockitoutil/TestBase.java
@@ -15,7 +15,7 @@ import org.junit.After;
 import org.junit.Before;
 import org.mockito.MockitoAnnotations;
 import org.mockito.StateMaster;
-import org.mockito.internal.MockitoCore;
+import org.mockito.internal.MockitoEngine;
 import org.mockito.internal.configuration.ConfigurationAccess;
 import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.invocation.InterceptedInvocation;
@@ -70,7 +70,7 @@ public class TestBase {
     }
 
     public static Invocation getLastInvocation() {
-        return new MockitoCore().getLastInvocation();
+        return new MockitoEngine().getLastInvocation();
     }
 
     protected static Invocation invocationOf(Class<?> type, String methodName, Object... args)
diff --git a/subprojects/android/src/main/java/org/mockito/android/internal/creation/AndroidByteBuddyMockMaker.java b/subprojects/android/src/main/java/org/mockito/android/internal/creation/AndroidByteBuddyMockMaker.java
index 64f6d70aa..375ae00ef 100644
--- a/subprojects/android/src/main/java/org/mockito/android/internal/creation/AndroidByteBuddyMockMaker.java
+++ b/subprojects/android/src/main/java/org/mockito/android/internal/creation/AndroidByteBuddyMockMaker.java
@@ -4,11 +4,11 @@
  */
 package org.mockito.android.internal.creation;
 
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.creation.bytebuddy.SubclassByteBuddyMockMaker;
 import org.mockito.internal.util.Platform;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 import org.mockito.plugins.MockMaker;
 
 import static org.mockito.internal.util.StringUtil.join;
@@ -21,7 +21,7 @@ public class AndroidByteBuddyMockMaker implements MockMaker {
         if (Platform.isAndroid() || Platform.isAndroidMockMakerRequired()) {
             delegate = new SubclassByteBuddyMockMaker(new AndroidLoadingStrategy());
         } else {
-            Plugins.getMockitoLogger()
+            PluginRegistry.getMockitoLogger()
                     .log(
                             join(
                                     "IMPORTANT NOTE FROM MOCKITO:",
@@ -36,7 +36,7 @@ public class AndroidByteBuddyMockMaker implements MockMaker {
     }
 
     @Override
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+    public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
         return delegate.createMock(settings, handler);
     }
 
@@ -46,7 +46,7 @@ public class AndroidByteBuddyMockMaker implements MockMaker {
     }
 
     @Override
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+    public void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings) {
         delegate.resetMock(mock, newHandler, settings);
     }
 
diff --git a/subprojects/extTest/src/test/java/org/mockitousage/plugins/donotmockenforcer/MyDoNotMockEnforcer.java b/subprojects/extTest/src/test/java/org/mockitousage/plugins/donotmockenforcer/MyDoNotMockEnforcer.java
index 73ca83017..52c11ce43 100644
--- a/subprojects/extTest/src/test/java/org/mockitousage/plugins/donotmockenforcer/MyDoNotMockEnforcer.java
+++ b/subprojects/extTest/src/test/java/org/mockitousage/plugins/donotmockenforcer/MyDoNotMockEnforcer.java
@@ -4,12 +4,12 @@
  */
 package org.mockitousage.plugins.donotmockenforcer;
 
-import org.mockito.plugins.DoNotMockEnforcer;
+import org.mockito.plugins.DoNotMockChecker;
 
-public class MyDoNotMockEnforcer implements DoNotMockEnforcer {
+public class MyDoNotMockEnforcer implements DoNotMockChecker {
 
     @Override
-    public String checkTypeForDoNotMockViolation(Class<?> type) {
+    public String checkTypeForDoNotMockRuleViolation(Class<?> type) {
         // Special case a type, because we want to opt-out of enforcing
         if (type.getName().endsWith("NotMockableButSpecialCased")) {
             return null;
diff --git a/subprojects/extTest/src/test/java/org/mockitousage/plugins/instantiator/MyInstantiatorProvider2.java b/subprojects/extTest/src/test/java/org/mockitousage/plugins/instantiator/MyInstantiatorProvider2.java
index e4238f3a6..e3e0a4374 100644
--- a/subprojects/extTest/src/test/java/org/mockitousage/plugins/instantiator/MyInstantiatorProvider2.java
+++ b/subprojects/extTest/src/test/java/org/mockitousage/plugins/instantiator/MyInstantiatorProvider2.java
@@ -7,13 +7,13 @@ package org.mockitousage.plugins.instantiator;
 import org.mockito.creation.instance.InstantiationException;
 import org.mockito.creation.instance.Instantiator;
 import org.mockito.internal.creation.instance.DefaultInstantiatorProvider;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 public class MyInstantiatorProvider2 extends DefaultInstantiatorProvider {
     static ThreadLocal<Boolean> explosive = new ThreadLocal<>();
 
     @Override
-    public Instantiator getInstantiator(MockCreationSettings<?> settings) {
+    public Instantiator getInstantiator(MockCreationOptions<?> settings) {
         if (explosive.get() != null) {
             throw new InstantiationException(MyInstantiatorProvider2.class.getName(), null);
         }
diff --git a/subprojects/extTest/src/test/java/org/mockitousage/plugins/switcher/MyMockMaker.java b/subprojects/extTest/src/test/java/org/mockitousage/plugins/switcher/MyMockMaker.java
index d412beda9..d4e4a0100 100644
--- a/subprojects/extTest/src/test/java/org/mockitousage/plugins/switcher/MyMockMaker.java
+++ b/subprojects/extTest/src/test/java/org/mockitousage/plugins/switcher/MyMockMaker.java
@@ -6,13 +6,13 @@ package org.mockitousage.plugins.switcher;
 
 import org.mockito.internal.creation.bytebuddy.SubclassByteBuddyMockMaker;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 public class MyMockMaker extends SubclassByteBuddyMockMaker {
 
     static ThreadLocal<Object> explosive = new ThreadLocal<Object>();
 
-    public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+    public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
         if (explosive.get() != null) {
             throw new RuntimeException(MyMockMaker.class.getName());
         }
@@ -23,7 +23,7 @@ public class MyMockMaker extends SubclassByteBuddyMockMaker {
         return super.getHandler(mock);
     }
 
-    public void resetMock(Object mock, MockHandler newHandler, MockCreationSettings settings) {
+    public void resetMock(Object mock, MockHandler newHandler, MockCreationOptions settings) {
         super.resetMock(mock, newHandler, settings);
     }
 
diff --git a/subprojects/inlineTest/src/test/java/org/mockitoinline/PluginTest.java b/subprojects/inlineTest/src/test/java/org/mockitoinline/PluginTest.java
index 163567e4e..cf42a92cc 100644
--- a/subprojects/inlineTest/src/test/java/org/mockitoinline/PluginTest.java
+++ b/subprojects/inlineTest/src/test/java/org/mockitoinline/PluginTest.java
@@ -5,7 +5,7 @@
 package org.mockitoinline;
 
 import org.junit.Test;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker;
 import org.mockito.internal.util.reflection.ModuleMemberAccessor;
 
@@ -15,11 +15,11 @@ public class PluginTest {
 
     @Test
     public void mock_maker_should_be_inline() throws Exception {
-        assertTrue(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker);
+        assertTrue(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker);
     }
 
     @Test
     public void member_accessor_should_be_module() throws Exception {
-        assertTrue(Plugins.getMemberAccessor() instanceof ModuleMemberAccessor);
+        assertTrue(PluginRegistry.getMemberAccessor() instanceof ModuleMemberAccessor);
     }
 }
diff --git a/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java b/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java
index e2dc009cb..fc7eb1f73 100644
--- a/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java
+++ b/subprojects/junit-jupiter/src/main/java/org/mockito/junit/jupiter/MockitoExtension.java
@@ -22,7 +22,7 @@ import org.junit.jupiter.api.extension.ParameterResolver;
 import org.mockito.Mockito;
 import org.mockito.MockitoSession;
 import org.mockito.ScopedMock;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.session.MockitoSessionLoggerAdapter;
 import org.mockito.junit.MockitoJUnitRunner;
 import org.mockito.junit.jupiter.resolver.CaptorParameterResolver;
@@ -156,7 +156,7 @@ public class MockitoExtension implements BeforeEachCallback, AfterEachCallback,
                 Mockito.mockitoSession()
                         .initMocks(testInstances.toArray())
                         .strictness(actualStrictness)
-                        .logger(new MockitoSessionLoggerAdapter(Plugins.getMockitoLogger()))
+                        .logger(new MockitoSessionLoggerAdapter(PluginRegistry.getMockitoLogger()))
                         .startMocking();
 
         context.getStore(MOCKITO).put(MOCKS, new HashSet<>());
diff --git a/subprojects/module-test/src/test/java/org/mockito/moduletest/ModuleAccessTest.java b/subprojects/module-test/src/test/java/org/mockito/moduletest/ModuleAccessTest.java
index ff10b1ac2..edf2cfe78 100644
--- a/subprojects/module-test/src/test/java/org/mockito/moduletest/ModuleAccessTest.java
+++ b/subprojects/module-test/src/test/java/org/mockito/moduletest/ModuleAccessTest.java
@@ -8,7 +8,7 @@ import org.junit.Assume;
 import org.junit.Test;
 import org.mockito.Mockito;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.util.reflection.ModuleMemberAccessor;
 import org.mockito.internal.util.reflection.ReflectionMemberAccessor;
 
@@ -80,7 +80,7 @@ public class ModuleAccessTest {
 
     @Test
     public void cannot_read_unopened_private_field_but_exception_includes_cause() throws Exception {
-        Assume.assumeThat(Plugins.getMemberAccessor(), not(instanceOf(ModuleMemberAccessor.class)));
+        Assume.assumeThat(PluginRegistry.getMemberAccessor(), not(instanceOf(ModuleMemberAccessor.class)));
 
         Path jar = modularJar(true, true, false, true);
         ModuleLayer layer = layer(jar, true, true);
@@ -101,7 +101,7 @@ public class ModuleAccessTest {
 
     @Test
     public void can_read_unopened_private_field_but_exception_includes_cause() throws Exception {
-        Assume.assumeThat(Plugins.getMemberAccessor(), instanceOf(ModuleMemberAccessor.class));
+        Assume.assumeThat(PluginRegistry.getMemberAccessor(), instanceOf(ModuleMemberAccessor.class));
 
         Path jar = modularJar(true, true, false, true);
         ModuleLayer layer = layer(jar, true, true);
diff --git a/subprojects/module-test/src/test/java/org/mockito/moduletest/ModuleHandlingTest.java b/subprojects/module-test/src/test/java/org/mockito/moduletest/ModuleHandlingTest.java
index 4e4314fbd..2db3f228e 100644
--- a/subprojects/module-test/src/test/java/org/mockito/moduletest/ModuleHandlingTest.java
+++ b/subprojects/module-test/src/test/java/org/mockito/moduletest/ModuleHandlingTest.java
@@ -10,7 +10,7 @@ import org.junit.runner.RunWith;
 import org.junit.runners.Parameterized;
 import org.mockito.Mockito;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.creation.bytebuddy.InlineByteBuddyMockMaker;
 import org.mockito.stubbing.OngoingStubbing;
 
@@ -44,7 +44,7 @@ public class ModuleHandlingTest {
 
     @Test
     public void can_define_class_in_open_reading_module() throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
 
         Path jar = modularJar(true, true, true);
         ModuleLayer layer = layer(jar, true, namedModules);
@@ -73,7 +73,7 @@ public class ModuleHandlingTest {
 
     @Test
     public void can_define_class_in_open_java_util_module() throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
 
         Path jar = modularJar(true, true, true);
         ModuleLayer layer = layer(jar, true, namedModules);
@@ -108,7 +108,7 @@ public class ModuleHandlingTest {
 
     @Test
     public void inline_mock_maker_can_mock_closed_modules() throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(true));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(true));
 
         Path jar = modularJar(false, false, false);
         ModuleLayer layer = layer(jar, false, namedModules);
@@ -131,7 +131,7 @@ public class ModuleHandlingTest {
 
     @Test
     public void can_define_class_in_open_reading_private_module() throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
 
         Path jar = modularJar(false, true, true);
         ModuleLayer layer = layer(jar, true, namedModules);
@@ -160,7 +160,7 @@ public class ModuleHandlingTest {
 
     @Test
     public void can_define_class_in_open_non_reading_module() throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
 
         Path jar = modularJar(true, true, true);
         ModuleLayer layer = layer(jar, false, namedModules);
@@ -189,7 +189,7 @@ public class ModuleHandlingTest {
 
     @Test
     public void can_define_class_in_open_non_reading_non_exporting_module() throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
 
         Path jar = modularJar(true, false, true);
         ModuleLayer layer = layer(jar, false, namedModules);
@@ -218,7 +218,7 @@ public class ModuleHandlingTest {
 
     @Test
     public void can_define_class_in_closed_module() throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
 
         Path jar = modularJar(true, true, false);
         ModuleLayer layer = layer(jar, false, namedModules);
@@ -255,7 +255,7 @@ public class ModuleHandlingTest {
     @Test
     public void cannot_define_class_in_non_opened_non_exported_module_if_lookup_injection()
             throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
         assumeThat(
                 !Boolean.getBoolean("org.mockito.internal.noUnsafeInjection")
                         && ClassInjector.UsingReflection.isAvailable(),
@@ -289,7 +289,7 @@ public class ModuleHandlingTest {
     @Test
     public void can_define_class_in_non_opened_non_exported_module_if_unsafe_injection()
             throws Exception {
-        assumeThat(Plugins.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
+        assumeThat(PluginRegistry.getMockMaker() instanceof InlineByteBuddyMockMaker, is(false));
         assumeThat(
                 !Boolean.getBoolean("org.mockito.internal.noUnsafeInjection")
                         && ClassInjector.UsingReflection.isAvailable(),
diff --git a/subprojects/osgi-test/src/test/java/org/mockito/osgitest/OsgiTest.java b/subprojects/osgi-test/src/test/java/org/mockito/osgitest/OsgiTest.java
index 5f96b4a3d..2d70bafde 100644
--- a/subprojects/osgi-test/src/test/java/org/mockito/osgitest/OsgiTest.java
+++ b/subprojects/osgi-test/src/test/java/org/mockito/osgitest/OsgiTest.java
@@ -7,13 +7,13 @@ package org.mockito.osgitest;
 import org.junit.runner.RunWith;
 import org.junit.runners.Suite;
 import org.junit.runners.model.RunnerBuilder;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.osgi.framework.Bundle;
 import org.osgi.framework.BundleContext;
 import org.osgi.framework.BundleException;
 import org.osgi.framework.Constants;
 import org.osgi.framework.launch.Framework;
 import org.osgi.framework.launch.FrameworkFactory;
-import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.plugins.InlineMockMaker;
 
 import java.io.File;
@@ -94,7 +94,7 @@ public class OsgiTest extends Suite {
     private static Class<?>[] getTestClasses() throws Exception {
         // The tests could not use 'Plugins' since 'org.mockito.internal' package is not exported.
         // Making the decision which tests to run depending on mock maker instance.
-        if (Plugins.getMockMaker() instanceof InlineMockMaker) {
+        if (PluginRegistry.getMockMaker() instanceof InlineMockMaker) {
             return new Class<?>[] {
                 loadTestClass("SimpleMockTest"),
                 loadTestClass("MockNonPublicClassTest"),
diff --git a/subprojects/programmatic-test/src/test/java/org/mockito/ProgrammaticMockMakerTest.java b/subprojects/programmatic-test/src/test/java/org/mockito/ProgrammaticMockMakerTest.java
index f03555d0e..6ec05aad2 100644
--- a/subprojects/programmatic-test/src/test/java/org/mockito/ProgrammaticMockMakerTest.java
+++ b/subprojects/programmatic-test/src/test/java/org/mockito/ProgrammaticMockMakerTest.java
@@ -16,7 +16,7 @@ import org.mockito.exceptions.base.MockitoException;
 import org.mockito.exceptions.verification.SmartNullPointerException;
 import org.mockito.internal.creation.bytebuddy.SubclassByteBuddyMockMaker;
 import org.mockito.invocation.MockHandler;
-import org.mockito.mock.MockCreationSettings;
+import org.mockito.mock.MockCreationOptions;
 
 public final class ProgrammaticMockMakerTest {
     @Test
@@ -194,7 +194,7 @@ public final class ProgrammaticMockMakerTest {
 
     public static class CustomMockMaker extends SubclassByteBuddyMockMaker {
         @Override
-        public <T> T createMock(MockCreationSettings<T> settings, MockHandler handler) {
+        public <T> T createMock(MockCreationOptions<T> settings, MockHandler handler) {
             throw new RuntimeException("CUSTOM MOCK MAKER");
         }
     }
diff --git a/subprojects/subclass/src/test/java/org/mockitosubclass/PluginTest.java b/subprojects/subclass/src/test/java/org/mockitosubclass/PluginTest.java
index c64ecbbe0..136a218c0 100644
--- a/subprojects/subclass/src/test/java/org/mockitosubclass/PluginTest.java
+++ b/subprojects/subclass/src/test/java/org/mockitosubclass/PluginTest.java
@@ -5,7 +5,7 @@
 package org.mockitosubclass;
 
 import org.junit.Test;
-import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.internal.configuration.plugins.PluginRegistry;
 import org.mockito.internal.creation.bytebuddy.ByteBuddyMockMaker;
 import org.mockito.internal.util.reflection.ModuleMemberAccessor;
 
@@ -15,11 +15,11 @@ public class PluginTest {
 
     @Test
     public void mock_maker_should_be_inline() throws Exception {
-        assertTrue(Plugins.getMockMaker() instanceof ByteBuddyMockMaker);
+        assertTrue(PluginRegistry.getMockMaker() instanceof ByteBuddyMockMaker);
     }
 
     @Test
     public void member_accessor_should_be_module() throws Exception {
-        assertTrue(Plugins.getMemberAccessor() instanceof ModuleMemberAccessor);
+        assertTrue(PluginRegistry.getMemberAccessor() instanceof ModuleMemberAccessor);
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

