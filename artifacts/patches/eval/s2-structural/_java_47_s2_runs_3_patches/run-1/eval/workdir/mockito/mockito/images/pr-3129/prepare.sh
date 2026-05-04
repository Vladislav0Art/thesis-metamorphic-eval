#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout edc624371009ce981bbc11b7d125ff4e359cff7e

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/org/mockito/Mockito.java b/src/main/java/org/mockito/Mockito.java
index ee5a13303..d9b0d3136 100644
--- a/src/main/java/org/mockito/Mockito.java
+++ b/src/main/java/org/mockito/Mockito.java
@@ -10,7 +10,7 @@ import org.mockito.internal.MockitoCore;
 import org.mockito.internal.creation.MockSettingsImpl;
 import org.mockito.internal.framework.DefaultMockitoFramework;
 import org.mockito.internal.session.DefaultMockitoSessionBuilder;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.verification.VerificationModeFactory;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationFactory;
@@ -23,7 +23,7 @@ import org.mockito.listeners.VerificationStartedEvent;
 import org.mockito.listeners.VerificationStartedListener;
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.api.MockitoPlugins;
 import org.mockito.quality.MockitoHint;
 import org.mockito.quality.Strictness;
 import org.mockito.session.MockitoSessionBuilder;
diff --git a/src/main/java/org/mockito/MockitoFramework.java b/src/main/java/org/mockito/MockitoFramework.java
index 020186f05..f8f9eb163 100644
--- a/src/main/java/org/mockito/MockitoFramework.java
+++ b/src/main/java/org/mockito/MockitoFramework.java
@@ -8,7 +8,7 @@ import org.mockito.exceptions.misusing.RedundantListenerException;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.InvocationFactory;
 import org.mockito.listeners.MockitoListener;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.api.MockitoPlugins;
 
 /**
  * Mockito framework settings and lifecycle listeners, for advanced users or for integrating with other frameworks.
diff --git a/src/main/java/org/mockito/internal/MockedStaticImpl.java b/src/main/java/org/mockito/internal/MockedStaticImpl.java
index f6705fb81..b1befeaa4 100644
--- a/src/main/java/org/mockito/internal/MockedStaticImpl.java
+++ b/src/main/java/org/mockito/internal/MockedStaticImpl.java
@@ -6,8 +6,8 @@ package org.mockito.internal;
 
 import static org.mockito.internal.exceptions.Reporter.missingMethodInvocation;
 import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
-import static org.mockito.internal.util.MockUtil.getInvocationContainer;
-import static org.mockito.internal.util.MockUtil.resetMock;
+import static org.mockito.util.MockUtil.getInvocationContainer;
+import static org.mockito.util.MockUtil.resetMock;
 import static org.mockito.internal.util.StringUtil.join;
 import static org.mockito.internal.verification.VerificationModeFactory.noInteractions;
 import static org.mockito.internal.verification.VerificationModeFactory.noMoreInteractions;
diff --git a/src/main/java/org/mockito/internal/MockitoCore.java b/src/main/java/org/mockito/internal/MockitoCore.java
index fd39f6a4a..2bde23f0a 100644
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
+import static org.mockito.util.MockUtil.createConstructionMock;
+import static org.mockito.util.MockUtil.createMock;
+import static org.mockito.util.MockUtil.createStaticMock;
+import static org.mockito.util.MockUtil.getInvocationContainer;
+import static org.mockito.util.MockUtil.getMockHandler;
+import static org.mockito.util.MockUtil.isMock;
+import static org.mockito.util.MockUtil.resetMock;
 import static org.mockito.internal.verification.VerificationModeFactory.noInteractions;
 import static org.mockito.internal.verification.VerificationModeFactory.noMoreInteractions;
 
@@ -49,7 +49,7 @@ import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.stubbing.OngoingStubbingImpl;
 import org.mockito.internal.stubbing.StubberImpl;
 import org.mockito.internal.util.DefaultMockingDetails;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.verification.MockAwareVerificationMode;
 import org.mockito.internal.verification.VerificationDataImpl;
 import org.mockito.internal.verification.VerificationModeFactory;
diff --git a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
index cd5194258..d4c1a3cb1 100644
--- a/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
+++ b/src/main/java/org/mockito/internal/configuration/SpyAnnotationEngine.java
@@ -23,7 +23,7 @@ import org.mockito.Mockito;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.plugins.AnnotationEngine;
 import org.mockito.plugins.MemberAccessor;
 
diff --git a/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java b/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
index bbfe88b85..64be12641 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/SpyOnInjectedFieldsHandler.java
@@ -13,7 +13,7 @@ import org.mockito.Mockito;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.util.reflection.FieldReader;
 import org.mockito.plugins.MemberAccessor;
 
diff --git a/src/main/java/org/mockito/internal/configuration/injection/filter/NameBasedCandidateFilter.java b/src/main/java/org/mockito/internal/configuration/injection/filter/NameBasedCandidateFilter.java
index b2cc6c75d..c9f0c1e4d 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/filter/NameBasedCandidateFilter.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/filter/NameBasedCandidateFilter.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.configuration.injection.filter;
 
-import static org.mockito.internal.util.MockUtil.getMockName;
+import static org.mockito.util.MockUtil.getMockName;
 
 import java.lang.reflect.Field;
 import java.util.ArrayList;
diff --git a/src/main/java/org/mockito/internal/configuration/injection/filter/TypeBasedCandidateFilter.java b/src/main/java/org/mockito/internal/configuration/injection/filter/TypeBasedCandidateFilter.java
index a62ee4053..1851d8777 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/filter/TypeBasedCandidateFilter.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/filter/TypeBasedCandidateFilter.java
@@ -17,7 +17,7 @@ import java.util.Collection;
 import java.util.List;
 import java.util.stream.Stream;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 
 public class TypeBasedCandidateFilter implements MockCandidateFilter {
 
diff --git a/src/main/java/org/mockito/internal/configuration/injection/scanner/MockScanner.java b/src/main/java/org/mockito/internal/configuration/injection/scanner/MockScanner.java
index 97984444c..6dd3b198a 100644
--- a/src/main/java/org/mockito/internal/configuration/injection/scanner/MockScanner.java
+++ b/src/main/java/org/mockito/internal/configuration/injection/scanner/MockScanner.java
@@ -11,7 +11,7 @@ import java.util.Set;
 
 import org.mockito.Mock;
 import org.mockito.Spy;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.util.reflection.FieldReader;
 
 /**
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java b/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
index 365c350e9..db6af10b2 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/DefaultMockitoPlugins.java
@@ -16,7 +16,7 @@ import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockitoLogger;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.api.MockitoPlugins;
 import org.mockito.plugins.PluginSwitch;
 import org.mockito.plugins.StackTraceCleanerProvider;
 
@@ -73,15 +73,20 @@ public class DefaultMockitoPlugins implements MockitoPlugins {
     }
 
     @Override
-    public <T> T getDefaultPlugin(Class<T> pluginType) {
-        String className = DEFAULT_PLUGINS.get(pluginType.getName());
-        return create(pluginType, className);
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
@@ -109,9 +114,4 @@ public class DefaultMockitoPlugins implements MockitoPlugins {
                     e);
         }
     }
-
-    @Override
-    public MockMaker getInlineMockMaker() {
-        return create(MockMaker.class, DEFAULT_PLUGINS.get(INLINE_ALIAS));
-    }
 }
diff --git a/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java b/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
index 20f6dc7bc..d09fbc2f2 100644
--- a/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
+++ b/src/main/java/org/mockito/internal/configuration/plugins/Plugins.java
@@ -13,7 +13,7 @@ import org.mockito.plugins.MemberAccessor;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockResolver;
 import org.mockito.plugins.MockitoLogger;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.api.MockitoPlugins;
 import org.mockito.plugins.StackTraceCleanerProvider;
 
 /** Access to Mockito behavior that can be reconfigured by plugins */
diff --git a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
index a1eed21e7..a686bfadf 100644
--- a/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
+++ b/src/main/java/org/mockito/internal/creation/bytebuddy/ByteBuddyCrossClassLoaderSerializationSupport.java
@@ -24,7 +24,7 @@ import java.util.concurrent.locks.ReentrantLock;
 import org.mockito.exceptions.base.MockitoSerializationIssue;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.creation.settings.CreationSettings;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.mock.MockCreationSettings;
 import org.mockito.mock.MockName;
 import org.mockito.mock.SerializableMode;
diff --git a/src/main/java/org/mockito/internal/exceptions/Reporter.java b/src/main/java/org/mockito/internal/exceptions/Reporter.java
index 060916846..26beedeac 100644
--- a/src/main/java/org/mockito/internal/exceptions/Reporter.java
+++ b/src/main/java/org/mockito/internal/exceptions/Reporter.java
@@ -46,7 +46,7 @@ import org.mockito.internal.debugging.LocationFactory;
 import org.mockito.internal.exceptions.util.ScenarioPrinter;
 import org.mockito.internal.junit.ExceptionFactory;
 import org.mockito.internal.matchers.LocalizedMatcher;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.verification.argumentmatching.ArgumentMatchingTool;
 import org.mockito.invocation.DescribedInvocation;
 import org.mockito.invocation.Invocation;
diff --git a/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java b/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
index f4a988231..61dc631ce 100644
--- a/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
+++ b/src/main/java/org/mockito/internal/framework/DefaultMockitoFramework.java
@@ -14,7 +14,7 @@ import org.mockito.invocation.InvocationFactory;
 import org.mockito.listeners.MockitoListener;
 import org.mockito.plugins.InlineMockMaker;
 import org.mockito.plugins.MockMaker;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.api.MockitoPlugins;
 
 public class DefaultMockitoFramework implements MockitoFramework {
 
diff --git a/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java b/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
index e58659a16..acd964312 100644
--- a/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
+++ b/src/main/java/org/mockito/internal/handler/MockHandlerImpl.java
@@ -14,7 +14,7 @@ import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.stubbing.OngoingStubbingImpl;
 import org.mockito.internal.stubbing.StubbedInvocationMatcher;
 import org.mockito.internal.stubbing.answers.DefaultAnswerValidator;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.verification.MockAwareVerificationMode;
 import org.mockito.internal.verification.VerificationDataImpl;
 import org.mockito.invocation.Invocation;
diff --git a/src/main/java/org/mockito/internal/reporting/PrintSettings.java b/src/main/java/org/mockito/internal/reporting/PrintSettings.java
index 41794adcb..5788f4c6d 100644
--- a/src/main/java/org/mockito/internal/reporting/PrintSettings.java
+++ b/src/main/java/org/mockito/internal/reporting/PrintSettings.java
@@ -12,7 +12,7 @@ import java.util.Set;
 
 import org.mockito.ArgumentMatcher;
 import org.mockito.internal.matchers.text.MatchersPrinter;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MatchableInvocation;
 
diff --git a/src/main/java/org/mockito/internal/stubbing/StubberImpl.java b/src/main/java/org/mockito/internal/stubbing/StubberImpl.java
index a357de641..b632beab7 100644
--- a/src/main/java/org/mockito/internal/stubbing/StubberImpl.java
+++ b/src/main/java/org/mockito/internal/stubbing/StubberImpl.java
@@ -9,7 +9,7 @@ import static org.mockito.internal.exceptions.Reporter.notAnException;
 import static org.mockito.internal.exceptions.Reporter.nullPassedToWhenMethod;
 import static org.mockito.internal.progress.ThreadSafeMockingProgress.mockingProgress;
 import static org.mockito.internal.stubbing.answers.DoesNothing.doesNothing;
-import static org.mockito.internal.util.MockUtil.isMock;
+import static org.mockito.util.MockUtil.isMock;
 
 import java.util.LinkedList;
 import java.util.List;
@@ -18,7 +18,7 @@ import org.mockito.internal.stubbing.answers.CallsRealMethods;
 import org.mockito.internal.stubbing.answers.Returns;
 import org.mockito.internal.stubbing.answers.ThrowsException;
 import org.mockito.internal.stubbing.answers.ThrowsExceptionForClassType;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.quality.Strictness;
 import org.mockito.stubbing.Answer;
 import org.mockito.stubbing.Stubber;
diff --git a/src/main/java/org/mockito/internal/stubbing/answers/AbstractThrowsException.java b/src/main/java/org/mockito/internal/stubbing/answers/AbstractThrowsException.java
index 6bcca9dc8..841fedccb 100644
--- a/src/main/java/org/mockito/internal/stubbing/answers/AbstractThrowsException.java
+++ b/src/main/java/org/mockito/internal/stubbing/answers/AbstractThrowsException.java
@@ -8,7 +8,7 @@ import static org.mockito.internal.exceptions.Reporter.cannotStubWithNullThrowab
 import static org.mockito.internal.exceptions.Reporter.checkedExceptionInvalid;
 
 import org.mockito.internal.exceptions.stacktrace.ConditionalStackTraceFilter;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.stubbing.Answer;
 import org.mockito.stubbing.ValidableAnswer;
diff --git a/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java b/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
index c159906af..434397081 100644
--- a/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
+++ b/src/main/java/org/mockito/internal/stubbing/answers/InvocationInfo.java
@@ -11,7 +11,7 @@ import java.util.Arrays;
 import java.util.List;
 
 import org.mockito.internal.invocation.AbstractAwareMethod;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.util.Primitives;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
index 8b64a1691..13482ffb4 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/RetrieveGenericsForDefaultAnswers.java
@@ -8,7 +8,7 @@ import java.lang.reflect.GenericArrayType;
 import java.lang.reflect.Type;
 import java.lang.reflect.TypeVariable;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.mock.MockCreationSettings;
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
index 27faed9d9..3892792f7 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsDeepStubs.java
@@ -5,7 +5,7 @@
 package org.mockito.internal.stubbing.defaultanswers;
 
 import static org.mockito.Mockito.withSettings;
-import static org.mockito.internal.util.MockUtil.typeMockabilityOf;
+import static org.mockito.util.MockUtil.typeMockabilityOf;
 
 import java.io.IOException;
 import java.io.Serializable;
@@ -16,7 +16,7 @@ import org.mockito.internal.MockitoCore;
 import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
 import org.mockito.internal.stubbing.StubbedInvocationMatcher;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.util.reflection.GenericMetadataSupport;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.mock.MockCreationSettings;
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsEmptyValues.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsEmptyValues.java
index c2dd0f7b2..45e06a4a4 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsEmptyValues.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsEmptyValues.java
@@ -33,7 +33,7 @@ import java.util.stream.IntStream;
 import java.util.stream.LongStream;
 import java.util.stream.Stream;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.internal.util.Primitives;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.mock.MockName;
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
index c15578091..7d749dae2 100755
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocks.java
@@ -8,7 +8,7 @@ import java.io.Serializable;
 
 import org.mockito.Mockito;
 import org.mockito.internal.creation.MockSettingsImpl;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.mock.MockCreationSettings;
 import org.mockito.stubbing.Answer;
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
index d538784a9..c883b970c 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/ReturnsSmartNulls.java
@@ -15,7 +15,7 @@ import org.mockito.Mockito;
 import org.mockito.internal.creation.MockSettingsImpl;
 import org.mockito.internal.creation.bytebuddy.MockAccess;
 import org.mockito.internal.debugging.LocationFactory;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.invocation.Location;
 import org.mockito.mock.MockCreationSettings;
diff --git a/src/main/java/org/mockito/internal/stubbing/defaultanswers/TriesToReturnSelf.java b/src/main/java/org/mockito/internal/stubbing/defaultanswers/TriesToReturnSelf.java
index f5643c565..d52d53ca4 100644
--- a/src/main/java/org/mockito/internal/stubbing/defaultanswers/TriesToReturnSelf.java
+++ b/src/main/java/org/mockito/internal/stubbing/defaultanswers/TriesToReturnSelf.java
@@ -6,7 +6,7 @@ package org.mockito.internal.stubbing.defaultanswers;
 
 import java.io.Serializable;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.invocation.InvocationOnMock;
 import org.mockito.stubbing.Answer;
 
diff --git a/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java b/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
index 1ad5a757f..7ec8b2dde 100644
--- a/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
+++ b/src/main/java/org/mockito/internal/util/DefaultMockingDetails.java
@@ -14,10 +14,11 @@ import org.mockito.invocation.Invocation;
 import org.mockito.invocation.MockHandler;
 import org.mockito.mock.MockCreationSettings;
 import org.mockito.stubbing.Stubbing;
+import org.mockito.util.MockUtil;
 
 /**
  * Class to inspect any object, and identify whether a particular object is either a mock or a spy.  This is
- * a wrapper for {@link org.mockito.internal.util.MockUtil}.
+ * a wrapper for {@link MockUtil}.
  */
 public class DefaultMockingDetails implements MockingDetails {
 
diff --git a/src/main/java/org/mockito/internal/util/MockCreationValidator.java b/src/main/java/org/mockito/internal/util/MockCreationValidator.java
index 9db6b36ea..b9e857aa5 100644
--- a/src/main/java/org/mockito/internal/util/MockCreationValidator.java
+++ b/src/main/java/org/mockito/internal/util/MockCreationValidator.java
@@ -14,6 +14,7 @@ import java.util.Collection;
 
 import org.mockito.mock.SerializableMode;
 import org.mockito.plugins.MockMaker.TypeMockability;
+import org.mockito.util.MockUtil;
 
 @SuppressWarnings("unchecked")
 public class MockCreationValidator {
diff --git a/src/main/java/org/mockito/internal/util/collections/HashCodeAndEqualsMockWrapper.java b/src/main/java/org/mockito/internal/util/collections/HashCodeAndEqualsMockWrapper.java
index 50e194db7..2dc374529 100644
--- a/src/main/java/org/mockito/internal/util/collections/HashCodeAndEqualsMockWrapper.java
+++ b/src/main/java/org/mockito/internal/util/collections/HashCodeAndEqualsMockWrapper.java
@@ -4,7 +4,7 @@
  */
 package org.mockito.internal.util.collections;
 
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 
 /**
  * hashCode and equals safe mock wrapper.
diff --git a/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java b/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
index 7d51a6bb1..b70b26de8 100644
--- a/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
+++ b/src/main/java/org/mockito/internal/util/reflection/FieldInitializer.java
@@ -6,7 +6,7 @@ package org.mockito.internal.util.reflection;
 
 import org.mockito.exceptions.base.MockitoException;
 import org.mockito.internal.configuration.plugins.Plugins;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.plugins.MemberAccessor;
 
 import java.lang.reflect.Constructor;
diff --git a/src/main/java/org/mockito/plugins/MockitoPlugins.java b/src/main/java/org/mockito/plugins/api/MockitoPlugins.java
similarity index 96%
rename from src/main/java/org/mockito/plugins/MockitoPlugins.java
rename to src/main/java/org/mockito/plugins/api/MockitoPlugins.java
index d911077fd..73953b72a 100644
--- a/src/main/java/org/mockito/plugins/MockitoPlugins.java
+++ b/src/main/java/org/mockito/plugins/api/MockitoPlugins.java
@@ -2,10 +2,11 @@
  * Copyright (c) 2017 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.plugins;
+package org.mockito.plugins.api;
 
 import org.mockito.Mockito;
 import org.mockito.MockitoFramework;
+import org.mockito.plugins.MockMaker;
 
 /**
  * Instance of this interface is available via {@link MockitoFramework#getPlugins()}.
@@ -19,6 +20,17 @@ import org.mockito.MockitoFramework;
  */
 public interface MockitoPlugins {
 
+    /**
+     * Returns inline mock maker, an optional mock maker that is bundled with Mockito distribution.
+     * This method is needed because {@link #getDefaultPlugin(Class)} does not provide an instance of inline mock maker.
+     * Creates new instance each time is called so it is recommended to keep hold of the resulting object for future invocations.
+     * For more information about inline mock maker see the javadoc for main {@link Mockito} class.
+     *
+     * @return instance of inline mock maker
+     * @since 2.10.0
+     */
+    MockMaker getInlineMockMaker();
+
     /**
      * Returns the default plugin implementation used by Mockito.
      * Mockito plugins are stateless so it is recommended to keep hold of the returned plugin implementation
@@ -30,15 +42,4 @@ public interface MockitoPlugins {
      * @since 2.10.0
      */
     <T> T getDefaultPlugin(Class<T> pluginType);
-
-    /**
-     * Returns inline mock maker, an optional mock maker that is bundled with Mockito distribution.
-     * This method is needed because {@link #getDefaultPlugin(Class)} does not provide an instance of inline mock maker.
-     * Creates new instance each time is called so it is recommended to keep hold of the resulting object for future invocations.
-     * For more information about inline mock maker see the javadoc for main {@link Mockito} class.
-     *
-     * @return instance of inline mock maker
-     * @since 2.10.0
-     */
-    MockMaker getInlineMockMaker();
 }
diff --git a/src/main/java/org/mockito/internal/util/MockUtil.java b/src/main/java/org/mockito/util/MockUtil.java
similarity index 99%
rename from src/main/java/org/mockito/internal/util/MockUtil.java
rename to src/main/java/org/mockito/util/MockUtil.java
index 0d80f6e19..023566b0b 100644
--- a/src/main/java/org/mockito/internal/util/MockUtil.java
+++ b/src/main/java/org/mockito/util/MockUtil.java
@@ -2,7 +2,7 @@
  * Copyright (c) 2007 Mockito contributors
  * This program is made available under the terms of the MIT License.
  */
-package org.mockito.internal.util;
+package org.mockito.util;
 
 import org.mockito.MockedConstruction;
 import org.mockito.Mockito;
@@ -11,6 +11,7 @@ import org.mockito.internal.configuration.plugins.DefaultMockitoPlugins;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.creation.settings.CreationSettings;
 import org.mockito.internal.stubbing.InvocationContainerImpl;
+import org.mockito.internal.util.MockNameImpl;
 import org.mockito.internal.util.reflection.LenientCopyTool;
 import org.mockito.invocation.MockHandler;
 import org.mockito.mock.MockCreationSettings;
@@ -34,71 +35,17 @@ public class MockUtil {
             new ConcurrentHashMap<>(
                     Collections.singletonMap(defaultMockMaker.getClass(), defaultMockMaker));
 
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
     public static TypeMockability typeMockabilityOf(Class<?> type, String mockMaker) {
         return getMockMaker(mockMaker).isTypeMockable(type);
     }
 
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
+    private static Object resolve(Object mock) {
+        if (mock instanceof Class<?>) { // static mocks are resolved by definition
+            return mock;
+        }
+        for (MockResolver mockResolver : Plugins.getMockResolvers()) {
+            mock = mockResolver.resolve(mock);
         }
-
         return mock;
     }
 
@@ -111,19 +58,15 @@ public class MockUtil {
         getMockMaker(settings.getMockMaker()).resetMock(mock, newHandler, settings);
     }
 
-    public static MockHandler<?> getMockHandler(Object mock) {
-        MockHandler handler = getMockHandlerOrNull(mock);
-        if (handler != null) {
-            return handler;
-        } else {
-            throw new NotAMockException("Argument should be a mock, but is: " + mock.getClass());
+    public static void maybeRedefineMockName(Object mock, String newName) {
+        MockName mockName = getMockName(mock);
+        // TODO SF hacky...
+        MockCreationSettings mockSettings = getMockHandler(mock).getMockSettings();
+        if (mockName.isDefault() && mockSettings instanceof CreationSettings) {
+            ((CreationSettings) mockSettings).setMockName(new MockNameImpl(newName));
         }
     }
 
-    public static InvocationContainerImpl getInvocationContainer(Object mock) {
-        return (InvocationContainerImpl) getMockHandler(mock).getInvocationContainer();
-    }
-
     public static boolean isSpy(Object mock) {
         return isMock(mock)
                 && getMockSettings(mock).getDefaultAnswer() == Mockito.CALLS_REAL_METHODS;
@@ -147,6 +90,52 @@ public class MockUtil {
         return getMockHandlerOrNull(mock) != null;
     }
 
+    public static MockCreationSettings getMockSettings(Object mock) {
+        return getMockHandler(mock).getMockSettings();
+    }
+
+    public static MockName getMockName(Object mock) {
+        return getMockHandler(mock).getMockSettings().getMockName();
+    }
+
+    private static MockMaker getMockMaker(String mockMaker) {
+        if (mockMaker == null) {
+            return defaultMockMaker;
+        }
+
+        String typeName;
+        if (DefaultMockitoPlugins.MOCK_MAKER_ALIASES.contains(mockMaker)) {
+            typeName = DefaultMockitoPlugins.getDefaultPluginClass(mockMaker);
+        } else {
+            typeName = mockMaker;
+        }
+
+        Class<? extends MockMaker> type;
+        // Using the context class loader because PluginInitializer.loadImpl is using it as well.
+        // Personally, I am suspicious whether the context class loader is a good choice in either
+        // of these cases.
+        ClassLoader loader = Thread.currentThread().getContextClassLoader();
+        if (loader == null) {
+            loader = ClassLoader.getSystemClassLoader();
+        }
+        try {
+            type = loader.loadClass(typeName).asSubclass(MockMaker.class);
+        } catch (Exception e) {
+            throw new IllegalStateException("Failed to load MockMaker: " + mockMaker, e);
+        }
+
+        return mockMakers.computeIfAbsent(
+                type,
+                t -> {
+                    try {
+                        return t.getDeclaredConstructor().newInstance();
+                    } catch (Exception e) {
+                        throw new IllegalStateException(
+                                "Failed to construct MockMaker: " + t.getName(), e);
+                    }
+                });
+    }
+
     private static MockHandler<?> getMockHandlerOrNull(Object mock) {
         if (mock == null) {
             throw new NotAMockException("Argument should be a mock, but is null!");
@@ -164,35 +153,17 @@ public class MockUtil {
         return null;
     }
 
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
+    public static MockHandler<?> getMockHandler(Object mock) {
+        MockHandler handler = getMockHandlerOrNull(mock);
+        if (handler != null) {
+            return handler;
+        } else {
+            throw new NotAMockException("Argument should be a mock, but is: " + mock.getClass());
         }
     }
 
-    public static MockCreationSettings getMockSettings(Object mock) {
-        return getMockHandler(mock).getMockSettings();
+    public static InvocationContainerImpl getInvocationContainer(Object mock) {
+        return (InvocationContainerImpl) getMockHandler(mock).getInvocationContainer();
     }
 
     public static <T> MockMaker.StaticMockControl<T> createStaticMock(
@@ -202,6 +173,30 @@ public class MockUtil {
         return mockMaker.createStaticMock(type, settings, handler);
     }
 
+    public static <T> T createMock(MockCreationSettings<T> settings) {
+        MockMaker mockMaker = getMockMaker(settings.getMockMaker());
+        MockHandler mockHandler = createMockHandler(settings);
+
+        Object spiedInstance = settings.getSpiedInstance();
+
+        T mock;
+        if (spiedInstance != null) {
+            mock =
+                    mockMaker
+                            .createSpy(settings, mockHandler, (T) spiedInstance)
+                            .orElseGet(
+                                    () -> {
+                                        T instance = mockMaker.createMock(settings, mockHandler);
+                                        new LenientCopyTool().copyToMock(spiedInstance, instance);
+                                        return instance;
+                                    });
+        } else {
+            mock = mockMaker.createMock(settings, mockHandler);
+        }
+
+        return mock;
+    }
+
     public static <T> MockMaker.ConstructionMockControl<T> createConstructionMock(
             Class<T> type,
             Function<MockedConstruction.Context, MockCreationSettings<T>> settingsFactory,
@@ -217,4 +212,10 @@ public class MockUtil {
             mockMaker.clearAllCaches();
         }
     }
+
+    public static boolean areSameMocks(Object mockA, Object mockB) {
+        return mockA == mockB || resolve(mockA) == resolve(mockB);
+    }
+
+    private MockUtil() {}
 }
diff --git a/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java b/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
index 3691412e5..a0d00b5d5 100755
--- a/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
+++ b/src/test/java/org/mockito/internal/stubbing/defaultanswers/ReturnsMocksTest.java
@@ -11,7 +11,7 @@ import static org.mockito.Mockito.when;
 import org.junit.Test;
 import org.mockito.internal.configuration.plugins.Plugins;
 import org.mockito.internal.stubbing.defaultanswers.ReturnsGenericDeepStubsTest.WithGenerics;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockitoutil.TestBase;
 
 public class ReturnsMocksTest extends TestBase {
diff --git a/src/test/java/org/mockito/internal/util/MockUtilTest.java b/src/test/java/org/mockito/internal/util/MockUtilTest.java
index 834178cde..0fadef12a 100644
--- a/src/test/java/org/mockito/internal/util/MockUtilTest.java
+++ b/src/test/java/org/mockito/internal/util/MockUtilTest.java
@@ -18,6 +18,7 @@ import org.junit.Test;
 import org.mockito.Mockito;
 import org.mockito.exceptions.misusing.NotAMockException;
 import org.mockito.internal.configuration.plugins.Plugins;
+import org.mockito.util.MockUtil;
 import org.mockitoutil.TestBase;
 
 @SuppressWarnings("unchecked")
diff --git a/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorIssue421Test.java b/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorIssue421Test.java
index 0e5c67f02..5d24ed5c8 100644
--- a/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorIssue421Test.java
+++ b/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorIssue421Test.java
@@ -10,7 +10,7 @@ import org.junit.Test;
 import org.junit.runner.RunWith;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.junit.MockitoJUnitRunner;
 import org.mockitousage.examples.use.ArticleCalculator;
 
diff --git a/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorTest.java b/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorTest.java
index c45c90ae2..794d63cd1 100644
--- a/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorTest.java
+++ b/src/test/java/org/mockitousage/annotation/MockInjectionUsingConstructorTest.java
@@ -29,7 +29,7 @@ import org.mockito.Mock;
 import org.mockito.MockitoAnnotations;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.junit.MockitoJUnitRunner;
 import org.mockitousage.IMethods;
 import org.mockitousage.examples.use.ArticleCalculator;
diff --git a/src/test/java/org/mockitousage/annotation/MockInjectionUsingSetterOrPropertyTest.java b/src/test/java/org/mockitousage/annotation/MockInjectionUsingSetterOrPropertyTest.java
index 0d2af98d6..2a6681222 100644
--- a/src/test/java/org/mockitousage/annotation/MockInjectionUsingSetterOrPropertyTest.java
+++ b/src/test/java/org/mockitousage/annotation/MockInjectionUsingSetterOrPropertyTest.java
@@ -20,7 +20,7 @@ import org.mockito.Mock;
 import org.mockito.MockitoAnnotations;
 import org.mockito.Spy;
 import org.mockito.exceptions.base.MockitoException;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockitousage.IMethods;
 import org.mockitoutil.TestBase;
 
diff --git a/src/test/java/org/mockitousage/annotation/SpyAnnotationInitializedInBaseClassTest.java b/src/test/java/org/mockitousage/annotation/SpyAnnotationInitializedInBaseClassTest.java
index 60f87913b..6cb494c4b 100644
--- a/src/test/java/org/mockitousage/annotation/SpyAnnotationInitializedInBaseClassTest.java
+++ b/src/test/java/org/mockitousage/annotation/SpyAnnotationInitializedInBaseClassTest.java
@@ -5,7 +5,7 @@
 package org.mockitousage.annotation;
 
 import static org.junit.Assert.assertTrue;
-import static org.mockito.internal.util.MockUtil.isMock;
+import static org.mockito.util.MockUtil.isMock;
 
 import java.util.LinkedList;
 import java.util.List;
@@ -14,7 +14,7 @@ import org.junit.Before;
 import org.junit.Test;
 import org.mockito.MockitoAnnotations;
 import org.mockito.Spy;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockitoutil.TestBase;
 
 @SuppressWarnings("unchecked")
diff --git a/src/test/java/org/mockitousage/annotation/SpyInjectionTest.java b/src/test/java/org/mockitousage/annotation/SpyInjectionTest.java
index 9961e6ee2..0165cccf8 100644
--- a/src/test/java/org/mockitousage/annotation/SpyInjectionTest.java
+++ b/src/test/java/org/mockitousage/annotation/SpyInjectionTest.java
@@ -10,7 +10,7 @@ import java.util.List;
 import org.junit.Test;
 import org.mockito.InjectMocks;
 import org.mockito.Spy;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockitoutil.TestBase;
 
 public class SpyInjectionTest extends TestBase {
diff --git a/src/test/java/org/mockitousage/debugging/VerboseLoggingOfInvocationsOnMockTest.java b/src/test/java/org/mockitousage/debugging/VerboseLoggingOfInvocationsOnMockTest.java
index 6696c12a5..33c16c8f6 100644
--- a/src/test/java/org/mockitousage/debugging/VerboseLoggingOfInvocationsOnMockTest.java
+++ b/src/test/java/org/mockitousage/debugging/VerboseLoggingOfInvocationsOnMockTest.java
@@ -17,7 +17,7 @@ import org.junit.Before;
 import org.junit.Test;
 import org.junit.runner.RunWith;
 import org.mockito.Mock;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.junit.MockitoJUnitRunner;
 
 /**
diff --git a/src/test/java/org/mockitousage/junitrule/JUnitTestRuleIntegratesWithRuleChainTest.java b/src/test/java/org/mockitousage/junitrule/JUnitTestRuleIntegratesWithRuleChainTest.java
index 498d2bc89..aa2979fb2 100644
--- a/src/test/java/org/mockitousage/junitrule/JUnitTestRuleIntegratesWithRuleChainTest.java
+++ b/src/test/java/org/mockitousage/junitrule/JUnitTestRuleIntegratesWithRuleChainTest.java
@@ -16,7 +16,7 @@ import org.junit.runner.JUnitCore;
 import org.junit.runner.Result;
 import org.junit.runners.model.Statement;
 import org.mockito.Mock;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.junit.MockitoJUnit;
 import org.mockito.quality.Strictness;
 import org.mockitousage.IMethods;
diff --git a/src/test/java/org/mockitousage/plugins/MockitoPluginsTest.java b/src/test/java/org/mockitousage/plugins/MockitoPluginsTest.java
index dd5f390a5..d212ee687 100644
--- a/src/test/java/org/mockitousage/plugins/MockitoPluginsTest.java
+++ b/src/test/java/org/mockitousage/plugins/MockitoPluginsTest.java
@@ -12,7 +12,7 @@ import org.mockito.plugins.AnnotationEngine;
 import org.mockito.plugins.InstantiatorProvider2;
 import org.mockito.plugins.MockMaker;
 import org.mockito.plugins.MockitoLogger;
-import org.mockito.plugins.MockitoPlugins;
+import org.mockito.plugins.api.MockitoPlugins;
 import org.mockito.plugins.PluginSwitch;
 import org.mockito.plugins.StackTraceCleanerProvider;
 import org.mockitoutil.TestBase;
diff --git a/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java b/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
index 31abe2e61..7b7055061 100644
--- a/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
+++ b/subprojects/junit-jupiter/src/test/java/org/mockitousage/JunitJupiterTest.java
@@ -11,7 +11,7 @@ import org.junit.jupiter.api.extension.ExtendWith;
 import org.mockito.InjectMocks;
 import org.mockito.Mock;
 import org.mockito.Mockito;
-import org.mockito.internal.util.MockUtil;
+import org.mockito.util.MockUtil;
 import org.mockito.junit.jupiter.MockitoExtension;
 
 import static org.assertj.core.api.Assertions.assertThat;

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./gradlew build || true

