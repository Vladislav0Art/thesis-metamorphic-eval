#!/bin/bash
set -e

cd /home/fastjson2
git config core.autocrlf input
git config core.filemode false
echo ".gitattributes" >> .git/info/exclude
echo "*.zip binary" >> .gitattributes
echo "*.png binary" >> .gitattributes
echo "*.jpg binary" >> .gitattributes
git add .
git reset --hard
bash /home/check_git_changes.sh
git checkout 6648b96c0162c222467eb44bac30a9d59392c7ff

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/core/src/main/java/com/alibaba/fastjson2/JSONReader.java b/core/src/main/java/com/alibaba/fastjson2/JSONReader.java
index 6fe6bc4d7..b6c06aefb 100644
--- a/core/src/main/java/com/alibaba/fastjson2/JSONReader.java
+++ b/core/src/main/java/com/alibaba/fastjson2/JSONReader.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2;
 
-import com.alibaba.fastjson2.filter.ContextAutoTypeBeforeHandler;
+import com.alibaba.fastjson2.filter.ContextAutoTypePreHandler;
 import com.alibaba.fastjson2.filter.ExtraProcessor;
 import com.alibaba.fastjson2.filter.Filter;
 import com.alibaba.fastjson2.reader.*;
@@ -3368,19 +3368,19 @@ public abstract class JSONReader
     }
 
     public static AutoTypeBeforeHandler autoTypeFilter(String... names) {
-        return new ContextAutoTypeBeforeHandler(names);
+        return new ContextAutoTypePreHandler(names);
     }
 
     public static AutoTypeBeforeHandler autoTypeFilter(boolean includeBasic, String... names) {
-        return new ContextAutoTypeBeforeHandler(includeBasic, names);
+        return new ContextAutoTypePreHandler(includeBasic, names);
     }
 
     public static AutoTypeBeforeHandler autoTypeFilter(Class... types) {
-        return new ContextAutoTypeBeforeHandler(types);
+        return new ContextAutoTypePreHandler(types);
     }
 
     public static AutoTypeBeforeHandler autoTypeFilter(boolean includeBasic, Class... types) {
-        return new ContextAutoTypeBeforeHandler(includeBasic, types);
+        return new ContextAutoTypePreHandler(includeBasic, types);
     }
 
     public static class Context {
diff --git a/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandler.java b/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandler.java
deleted file mode 100644
index e3d0d3a4e..000000000
--- a/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandler.java
+++ /dev/null
@@ -1,329 +0,6 @@
-package com.alibaba.fastjson2.filter;
-
-import com.alibaba.fastjson2.JSON;
-import com.alibaba.fastjson2.JSONReader;
-import com.alibaba.fastjson2.util.Fnv;
-import com.alibaba.fastjson2.util.TypeUtils;
-
-import java.math.BigDecimal;
-import java.math.BigInteger;
-import java.text.SimpleDateFormat;
-import java.time.Instant;
-import java.time.LocalDate;
-import java.time.LocalDateTime;
-import java.time.LocalTime;
-import java.time.format.DateTimeFormatter;
 import java.util.*;
 import java.util.concurrent.*;
 import java.util.concurrent.atomic.*;
 
-import static com.alibaba.fastjson2.util.Fnv.MAGIC_HASH_CODE;
-import static com.alibaba.fastjson2.util.Fnv.MAGIC_PRIME;
 import static com.alibaba.fastjson2.util.TypeUtils.*;
 
-public class ContextAutoTypeBeforeHandler
-        implements JSONReader.AutoTypeBeforeHandler {
-    static final Class[] BASIC_TYPES = {
-            Object.class,
-            byte.class,
-            Byte.class,
-            short.class,
-            Short.class,
-            int.class,
-            Integer.class,
-            long.class,
-            Long.class,
-            float.class,
-            Float.class,
-            double.class,
-            Double.class,
-
-            Number.class,
-            BigInteger.class,
-            BigDecimal.class,
-
-            AtomicInteger.class,
-            AtomicLong.class,
-            AtomicBoolean.class,
-            AtomicIntegerArray.class,
-            AtomicLongArray.class,
-            AtomicReference.class,
-
-            boolean.class,
-            Boolean.class,
-            char.class,
-            Character.class,
-
-            String.class,
-            UUID.class,
-            Currency.class,
-            BitSet.class,
-            EnumSet.class,
-
-            Date.class,
-            Calendar.class,
-            LocalTime.class,
-            LocalDate.class,
-            LocalDateTime.class,
-            Instant.class,
-            SimpleDateFormat.class,
-            DateTimeFormatter.class,
-            TimeUnit.class,
-
-            Set.class,
-            HashSet.class,
-            LinkedHashSet.class,
-            TreeSet.class,
-            List.class,
-            ArrayList.class,
-            LinkedList.class,
-            ConcurrentLinkedQueue.class,
-            ConcurrentSkipListSet.class,
-            CopyOnWriteArrayList.class,
-
-            Collections.emptyList().getClass(),
-            Collections.emptyMap().getClass(),
-            CLASS_SINGLE_SET,
-            CLASS_UNMODIFIABLE_COLLECTION,
-            CLASS_UNMODIFIABLE_LIST,
-            CLASS_UNMODIFIABLE_SET,
-            CLASS_UNMODIFIABLE_SORTED_SET,
-            CLASS_UNMODIFIABLE_NAVIGABLE_SET,
-            Collections.unmodifiableMap(new HashMap<>()).getClass(),
-            Collections.unmodifiableNavigableMap(new TreeMap<>()).getClass(),
-            Collections.unmodifiableSortedMap(new TreeMap<>()).getClass(),
-            Arrays.asList().getClass(),
-
-            Map.class,
-            HashMap.class,
-            Hashtable.class,
-            TreeMap.class,
-            LinkedHashMap.class,
-            WeakHashMap.class,
-            IdentityHashMap.class,
-            ConcurrentMap.class,
-            ConcurrentHashMap.class,
-            ConcurrentSkipListMap.class,
-
-            Exception.class,
-            IllegalAccessError.class,
-            IllegalAccessException.class,
-            IllegalArgumentException.class,
-            IllegalMonitorStateException.class,
-            IllegalStateException.class,
-            IllegalThreadStateException.class,
-            IndexOutOfBoundsException.class,
-            InstantiationError.class,
-            InstantiationException.class,
-            InternalError.class,
-            InterruptedException.class,
-            LinkageError.class,
-            NegativeArraySizeException.class,
-            NoClassDefFoundError.class,
-            NoSuchFieldError.class,
-            NoSuchFieldException.class,
-            NoSuchMethodError.class,
-            NoSuchMethodException.class,
-            NullPointerException.class,
-            NumberFormatException.class,
-            OutOfMemoryError.class,
-            RuntimeException.class,
-            SecurityException.class,
-            StackOverflowError.class,
-            StringIndexOutOfBoundsException.class,
-            TypeNotPresentException.class,
-            VerifyError.class,
-            StackTraceElement.class
-    };
-
-    final long[] acceptHashCodes;
-    final ConcurrentMap<Integer, ConcurrentHashMap<Long, Class>> tclHashCaches = new ConcurrentHashMap<>();
-    final Map<Long, Class> classCache = new ConcurrentHashMap<>(16, 0.75f, 1);
-
-    public ContextAutoTypeBeforeHandler(Class... types) {
-        this(false, types);
-    }
-
-    public ContextAutoTypeBeforeHandler(boolean includeBasic, Class... types) {
-        this(
-                includeBasic,
-                names(
-                        Arrays.asList(types)
-                )
-        );
-    }
-
-    public ContextAutoTypeBeforeHandler(String... acceptNames) {
-        this(false, acceptNames);
-    }
-
-    public ContextAutoTypeBeforeHandler(boolean includeBasic) {
-        this(includeBasic, new String[0]);
-    }
-
-    static String[] names(Collection<Class> types) {
-        Set<String> nameSet = new HashSet<>();
-        for (Class type : types) {
-            if (type == null) {
-                continue;
-            }
-
-            String name = TypeUtils.getTypeName(type);
-            nameSet.add(name);
-        }
-        return nameSet.toArray(new String[nameSet.size()]);
-    }
-
-    public ContextAutoTypeBeforeHandler(boolean includeBasic, String... acceptNames) {
-        Set<String> nameSet = new HashSet<>();
-        if (includeBasic) {
-            for (Class basicType : BASIC_TYPES) {
-                String name = TypeUtils.getTypeName(basicType);
-                nameSet.add(name);
-            }
-        }
-
-        for (String name : acceptNames) {
-            if (name == null || name.isEmpty()) {
-                continue;
-            }
-
-            Class mapping = TypeUtils.getMapping(name);
-            if (mapping != null) {
-                name = TypeUtils.getTypeName(mapping);
-            }
-            nameSet.add(name);
-        }
-
-        long[] array = new long[nameSet.size()];
-
-        int index = 0;
-        for (String name : nameSet) {
-            long hashCode = MAGIC_HASH_CODE;
-            for (int j = 0; j < name.length(); ++j) {
-                char ch = name.charAt(j);
-                if (ch == '$') {
-                    ch = '.';
-                }
-                hashCode ^= ch;
-                hashCode *= MAGIC_PRIME;
-            }
-
-            array[index++] = hashCode;
-        }
-
-        if (index != array.length) {
-            array = Arrays.copyOf(array, index);
-        }
-        Arrays.sort(array);
-        this.acceptHashCodes = array;
-    }
-
-    public Class<?> apply(long typeNameHash, Class<?> expectClass, long features) {
-        ClassLoader tcl = Thread.currentThread().getContextClassLoader();
-        if (tcl != null && tcl != JSON.class.getClassLoader()) {
-            int tclHash = System.identityHashCode(tcl);
-            ConcurrentHashMap<Long, Class> tclHashCache = tclHashCaches.get(tclHash);
-            if (tclHashCache != null) {
-                return tclHashCache.get(typeNameHash);
-            }
-        }
-
-        return classCache.get(typeNameHash);
-    }
-
-    @Override
-    public Class<?> apply(String typeName, Class<?> expectClass, long features) {
-        if ("O".equals(typeName)) {
-            typeName = "Object";
-        }
-
-        long hash = MAGIC_HASH_CODE;
-        for (int i = 0, typeNameLength = typeName.length(); i < typeNameLength; ++i) {
-            char ch = typeName.charAt(i);
-            if (ch == '$') {
-                ch = '.';
-            }
-            hash ^= ch;
-            hash *= MAGIC_PRIME;
-
-            if (Arrays.binarySearch(acceptHashCodes, hash) >= 0) {
-                long typeNameHash = Fnv.hashCode64(typeName);
-                Class clazz = apply(typeNameHash, expectClass, features);
-
-                if (clazz == null) {
-                    clazz = loadClass(typeName);
-                    if (clazz != null) {
-                        Class origin = putCacheIfAbsent(typeNameHash, clazz);
-                        if (origin != null) {
-                            clazz = origin;
-                        }
-                    }
-                }
-
-                if (clazz != null) {
-                    return clazz;
-                }
-            }
-        }
-
-        long typeNameHash = Fnv.hashCode64(typeName);
-
-        if (typeName.length() > 0
-                && typeName.charAt(0) == '[') {
-            Class clazz = apply(typeNameHash, expectClass, features);
-            if (clazz != null) {
-                return clazz;
-            }
-
-            String itemTypeName = typeName.substring(1);
-            Class itemExpectClass = null;
-            if (expectClass != null) {
-                itemExpectClass = expectClass.getComponentType();
-            }
-            Class itemType = apply(itemTypeName, itemExpectClass, features);
-            if (itemType != null) {
-                Class arrayType;
-                if (itemType == itemExpectClass) {
-                    arrayType = expectClass;
-                } else {
-                    arrayType = TypeUtils.getArrayClass(itemType);
-                }
-                Class origin = putCacheIfAbsent(typeNameHash, arrayType);
-                if (origin != null) {
-                    arrayType = origin;
-                }
-                return arrayType;
-            }
-        }
-
-        Class mapping = TypeUtils.getMapping(typeName);
-        if (mapping != null) {
-            String mappingTypeName = TypeUtils.getTypeName(mapping);
-            if (!typeName.equals(mappingTypeName)) {
-                Class<?> mappingClass = apply(mappingTypeName, expectClass, features);
-                if (mappingClass != null) {
-                    putCacheIfAbsent(typeNameHash, mappingClass);
-                }
-                return mappingClass;
-            }
-        }
-
-        return null;
-    }
-
-    private Class putCacheIfAbsent(long typeNameHash, Class type) {
-        ClassLoader tcl = Thread.currentThread().getContextClassLoader();
-        if (tcl != null && tcl != JSON.class.getClassLoader()) {
-            int tclHash = System.identityHashCode(tcl);
-            ConcurrentHashMap<Long, Class> tclHashCache = tclHashCaches.get(tclHash);
-            if (tclHashCache == null) {
-                tclHashCaches.putIfAbsent(tclHash, new ConcurrentHashMap<>());
-                tclHashCache = tclHashCaches.get(tclHash);
-            }
-
-            return tclHashCache.putIfAbsent(typeNameHash, type);
-        }
-        return classCache.putIfAbsent(typeNameHash, type);
-    }
-}
diff --git a/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypePreHandler.java b/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypePreHandler.java
new file mode 100644
index 000000000..7f1573469
--- /dev/null
+++ b/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypePreHandler.java
@@ -0,0 +1,329 @@
+package com.alibaba.fastjson2.filter;
+
+import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JSONReader;
+import com.alibaba.fastjson2.util.Fnv;
+import com.alibaba.fastjson2.util.TypeUtils;
+
+import java.math.BigDecimal;
+import java.math.BigInteger;
+import java.text.SimpleDateFormat;
+import java.time.Instant;
+import java.time.LocalDate;
+import java.time.LocalDateTime;
+import java.time.LocalTime;
+import java.time.format.DateTimeFormatter;
+import java.util.*;
+import java.util.concurrent.*;
+import java.util.concurrent.atomic.*;
+
+import static com.alibaba.fastjson2.util.Fnv.MAGIC_HASH_CODE;
+import static com.alibaba.fastjson2.util.Fnv.MAGIC_PRIME;
+import static com.alibaba.fastjson2.util.TypeUtils.*;
+
+public class ContextAutoTypePreHandler
+        implements JSONReader.AutoTypeBeforeHandler {
+    static final Class[] CORE_BASIC_CLASSES = {
+            Object.class,
+            byte.class,
+            Byte.class,
+            short.class,
+            Short.class,
+            int.class,
+            Integer.class,
+            long.class,
+            Long.class,
+            float.class,
+            Float.class,
+            double.class,
+            Double.class,
+
+            Number.class,
+            BigInteger.class,
+            BigDecimal.class,
+
+            AtomicInteger.class,
+            AtomicLong.class,
+            AtomicBoolean.class,
+            AtomicIntegerArray.class,
+            AtomicLongArray.class,
+            AtomicReference.class,
+
+            boolean.class,
+            Boolean.class,
+            char.class,
+            Character.class,
+
+            String.class,
+            UUID.class,
+            Currency.class,
+            BitSet.class,
+            EnumSet.class,
+
+            Date.class,
+            Calendar.class,
+            LocalTime.class,
+            LocalDate.class,
+            LocalDateTime.class,
+            Instant.class,
+            SimpleDateFormat.class,
+            DateTimeFormatter.class,
+            TimeUnit.class,
+
+            Set.class,
+            HashSet.class,
+            LinkedHashSet.class,
+            TreeSet.class,
+            List.class,
+            ArrayList.class,
+            LinkedList.class,
+            ConcurrentLinkedQueue.class,
+            ConcurrentSkipListSet.class,
+            CopyOnWriteArrayList.class,
+
+            Collections.emptyList().getClass(),
+            Collections.emptyMap().getClass(),
+            CLASS_SINGLE_SET,
+            CLASS_UNMODIFIABLE_COLLECTION,
+            CLASS_UNMODIFIABLE_LIST,
+            CLASS_UNMODIFIABLE_SET,
+            CLASS_UNMODIFIABLE_SORTED_SET,
+            CLASS_UNMODIFIABLE_NAVIGABLE_SET,
+            Collections.unmodifiableMap(new HashMap<>()).getClass(),
+            Collections.unmodifiableNavigableMap(new TreeMap<>()).getClass(),
+            Collections.unmodifiableSortedMap(new TreeMap<>()).getClass(),
+            Arrays.asList().getClass(),
+
+            Map.class,
+            HashMap.class,
+            Hashtable.class,
+            TreeMap.class,
+            LinkedHashMap.class,
+            WeakHashMap.class,
+            IdentityHashMap.class,
+            ConcurrentMap.class,
+            ConcurrentHashMap.class,
+            ConcurrentSkipListMap.class,
+
+            Exception.class,
+            IllegalAccessError.class,
+            IllegalAccessException.class,
+            IllegalArgumentException.class,
+            IllegalMonitorStateException.class,
+            IllegalStateException.class,
+            IllegalThreadStateException.class,
+            IndexOutOfBoundsException.class,
+            InstantiationError.class,
+            InstantiationException.class,
+            InternalError.class,
+            InterruptedException.class,
+            LinkageError.class,
+            NegativeArraySizeException.class,
+            NoClassDefFoundError.class,
+            NoSuchFieldError.class,
+            NoSuchFieldException.class,
+            NoSuchMethodError.class,
+            NoSuchMethodException.class,
+            NullPointerException.class,
+            NumberFormatException.class,
+            OutOfMemoryError.class,
+            RuntimeException.class,
+            SecurityException.class,
+            StackOverflowError.class,
+            StringIndexOutOfBoundsException.class,
+            TypeNotPresentException.class,
+            VerifyError.class,
+            StackTraceElement.class
+    };
+
+    final long[] allowedHashCodes;
+    final ConcurrentMap<Integer, ConcurrentHashMap<Long, Class>> classLoaderHashCaches = new ConcurrentHashMap<>();
+    final Map<Long, Class> cachedClassesByHash = new ConcurrentHashMap<>(16, 0.75f, 1);
+
+    public ContextAutoTypePreHandler(Class... typeArray) {
+        this.ContextAutoTypePreHandler(false, typeArray);
+    }
+
+    public ContextAutoTypePreHandler(boolean includeCoreTypes, Class... typeArray) {
+        this(
+                includeCoreTypes,
+                getTypeNames(
+                        Arrays.asList(typeArray)
+                )
+        );
+    }
+
+    public ContextAutoTypePreHandler(String... allowedNames) {
+        this.ContextAutoTypePreHandler(false, allowedNames);
+    }
+
+    public ContextAutoTypePreHandler(boolean includeCoreTypes) {
+        this.ContextAutoTypePreHandler(includeCoreTypes, new String[0]);
+    }
+
+    static String[] getTypeNames(Collection<Class> typeArray) {
+        Set<String> namesHashSet = new HashSet<>();
+        for (Class inputType : typeArray) {
+            if (inputType == null) {
+                continue;
+            }
+
+            String candidateName = TypeUtils.getTypeName(inputType);
+            namesHashSet.add(candidateName);
+        }
+        return namesHashSet.toArray(new String[namesHashSet.size()]);
+    }
+
+    public ContextAutoTypePreHandler(boolean includeCoreTypes, String... allowedNames) {
+        Set<String> namesHashSet = new HashSet<>();
+        if (includeCoreTypes) {
+            for (Class coreType : CORE_BASIC_CLASSES) {
+                String candidateName = TypeUtils.getTypeName(coreType);
+                namesHashSet.add(candidateName);
+            }
+        }
+
+        for (String candidateName : allowedNames) {
+            if (candidateName == null || candidateName.isEmpty()) {
+                continue;
+            }
+
+            Class mappedClass = TypeUtils.getMapping(candidateName);
+            if (mappedClass != null) {
+                candidateName = TypeUtils.getTypeName(mappedClass);
+            }
+            namesHashSet.add(candidateName);
+        }
+
+        long[] hashArray = new long[namesHashSet.size()];
+
+        int idx = 0;
+        for (String candidateName : namesHashSet) {
+            long computedHash = MAGIC_HASH_CODE;
+            for (int pos = 0; pos < candidateName.length(); ++pos) {
+                char currentChar = candidateName.charAt(pos);
+                if (currentChar == '$') {
+                    currentChar = '.';
+                }
+                computedHash ^= currentChar;
+                computedHash *= MAGIC_PRIME;
+            }
+
+            hashArray[idx++] = computedHash;
+        }
+
+        if (idx != hashArray.length) {
+            hashArray = Arrays.copyOf(hashArray, idx);
+        }
+        Arrays.sort(hashArray);
+        this.allowedHashCodes = hashArray;
+    }
+
+    public Class<?> apply(long typeHashValue, Class<?> expectedClass, long featureFlags) {
+        ClassLoader classLoader = Thread.currentThread().getContextClassLoader();
+        if (classLoader != null && classLoader != JSON.class.getClassLoader()) {
+            int loaderHash = System.identityHashCode(classLoader);
+            ConcurrentHashMap<Long, Class> loaderHashCache = classLoaderHashCaches.get(loaderHash);
+            if (loaderHashCache != null) {
+                return loaderHashCache.get(typeHashValue);
+            }
+        }
+
+        return cachedClassesByHash.get(typeHashValue);
+    }
+
+    @Override
+    public Class<?> apply(String requestedTypeName, Class<?> expectedClass, long featureFlags) {
+        if ("O".equals(requestedTypeName)) {
+            requestedTypeName = "Object";
+        }
+
+        long hashValue = MAGIC_HASH_CODE;
+        for (int idx = 0, nameLength = requestedTypeName.length(); idx < nameLength; ++idx) {
+            char currentChar = requestedTypeName.charAt(idx);
+            if (currentChar == '$') {
+                currentChar = '.';
+            }
+            hashValue ^= currentChar;
+            hashValue *= MAGIC_PRIME;
+
+            if (Arrays.binarySearch(allowedHashCodes, hashValue) >= 0) {
+                long typeHashValue = Fnv.hashCode64(requestedTypeName);
+                Class resolvedClass = apply(typeHashValue, expectedClass, featureFlags);
+
+                if (resolvedClass == null) {
+                    resolvedClass = loadClass(requestedTypeName);
+                    if (resolvedClass != null) {
+                        Class originalClass = putIfAbsentInCache(typeHashValue, resolvedClass);
+                        if (originalClass != null) {
+                            resolvedClass = originalClass;
+                        }
+                    }
+                }
+
+                if (resolvedClass != null) {
+                    return resolvedClass;
+                }
+            }
+        }
+
+        long typeHashValue = Fnv.hashCode64(requestedTypeName);
+
+        if (requestedTypeName.length() > 0
+                && requestedTypeName.charAt(0) == '[') {
+            Class resolvedClass = apply(typeHashValue, expectedClass, featureFlags);
+            if (resolvedClass != null) {
+                return resolvedClass;
+            }
+
+            String elementTypeName = requestedTypeName.substring(1);
+            Class expectedItemClass = null;
+            if (expectedClass != null) {
+                expectedItemClass = expectedClass.getComponentType();
+            }
+            Class itemClassType = apply(elementTypeName, expectedItemClass, featureFlags);
+            if (itemClassType != null) {
+                Class arrayElementType;
+                if (itemClassType == expectedItemClass) {
+                    arrayElementType = expectedClass;
+                } else {
+                    arrayElementType = TypeUtils.getArrayClass(itemClassType);
+                }
+                Class originalClass = putIfAbsentInCache(typeHashValue, arrayElementType);
+                if (originalClass != null) {
+                    arrayElementType = originalClass;
+                }
+                return arrayElementType;
+            }
+        }
+
+        Class mappedClass = TypeUtils.getMapping(requestedTypeName);
+        if (mappedClass != null) {
+            String mappedTypeName = TypeUtils.getTypeName(mappedClass);
+            if (!requestedTypeName.equals(mappedTypeName)) {
+                Class<?> mappingTargetClass = apply(mappedTypeName, expectedClass, featureFlags);
+                if (mappingTargetClass != null) {
+                    putIfAbsentInCache(typeHashValue, mappingTargetClass);
+                }
+                return mappingTargetClass;
+            }
+        }
+
+        return null;
+    }
+
+    private Class putIfAbsentInCache(long typeHashValue, Class inputType) {
+        ClassLoader classLoader = Thread.currentThread().getContextClassLoader();
+        if (classLoader != null && classLoader != JSON.class.getClassLoader()) {
+            int loaderHash = System.identityHashCode(classLoader);
+            ConcurrentHashMap<Long, Class> loaderHashCache = classLoaderHashCaches.get(loaderHash);
+            if (loaderHashCache == null) {
+                classLoaderHashCaches.putIfAbsent(loaderHash, new ConcurrentHashMap<>());
+                loaderHashCache = classLoaderHashCaches.get(loaderHash);
+            }
+
+            return loaderHashCache.putIfAbsent(typeHashValue, inputType);
+        }
+        return cachedClassesByHash.putIfAbsent(typeHashValue, inputType);
+    }
+}
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderList.java b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderList.java
index 162747517..c13af9e7d 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderList.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderList.java
@@ -76,7 +76,7 @@ public class FieldReaderList<T, V>
         if (initReader != null) {
             builder = this.initReader.getBuildFunction();
         } else {
-            if (objectReader instanceof ObjectReaderImplList) {
+            if (objectReader instanceof ListObjectReaderImpl) {
                 builder = objectReader.getBuildFunction();
             }
         }
@@ -276,10 +276,10 @@ public class FieldReaderList<T, V>
                 autoTypeObjectReader = context.getObjectReaderAutoType(typeName, fieldClass, features);
             }
 
-            if (autoTypeObjectReader instanceof ObjectReaderImplList) {
-                ObjectReaderImplList listReader = (ObjectReaderImplList) autoTypeObjectReader;
+            if (autoTypeObjectReader instanceof ListObjectReaderImpl) {
+                ListObjectReaderImpl listReader = (ListObjectReaderImpl) autoTypeObjectReader;
 
-                autoTypeObjectReader = new ObjectReaderImplList(fieldType, fieldClass, listReader.instanceType, itemType, listReader.builder);
+                autoTypeObjectReader = new ListObjectReaderImpl(fieldType, fieldClass, listReader.instanceClassType, itemType, listReader.factory);
             }
 
             if (autoTypeObjectReader == null) {
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderObject.java b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderObject.java
index c51d893a5..a16a86003 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderObject.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderObject.java
@@ -58,7 +58,7 @@ public class FieldReaderObject<T>
         if (fieldClass != null && Map.class.isAssignableFrom(fieldClass)) {
             return reader = ObjectReaderImplMap.of(fieldType, fieldClass, features);
         } else if (fieldClass != null && Collection.class.isAssignableFrom(fieldClass)) {
-            return reader = ObjectReaderImplList.of(fieldType, fieldClass, features);
+            return reader = ListObjectReaderImpl.ofType(fieldType, fieldClass, features);
         }
 
         return reader = jsonReader.getObjectReader(fieldType);
@@ -77,7 +77,7 @@ public class FieldReaderObject<T>
         if (Map.class.isAssignableFrom(fieldClass)) {
             return reader = ObjectReaderImplMap.of(fieldType, fieldClass, features);
         } else if (Collection.class.isAssignableFrom(fieldClass)) {
-            return reader = ObjectReaderImplList.of(fieldType, fieldClass, features);
+            return reader = ListObjectReaderImpl.ofType(fieldType, fieldClass, features);
         }
 
         return reader = context.getObjectReader(fieldType);
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ListObjectReaderImpl.java b/core/src/main/java/com/alibaba/fastjson2/reader/ListObjectReaderImpl.java
new file mode 100644
index 000000000..4aa82d281
--- /dev/null
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ListObjectReaderImpl.java
@@ -0,0 +1,553 @@
+package com.alibaba.fastjson2.reader;
+
+import com.alibaba.fastjson2.*;
+import com.alibaba.fastjson2.util.Fnv;
+import com.alibaba.fastjson2.util.GuavaSupport;
+import com.alibaba.fastjson2.util.TypeUtils;
+
+import java.lang.reflect.ParameterizedType;
+import java.lang.reflect.Type;
+import java.util.*;
+import java.util.function.Function;
+
+import static com.alibaba.fastjson2.util.JDKUtils.JVM_VERSION;
+
+public final class ListObjectReaderImpl
+        implements ObjectReader {
+    static final Class EMPTY_SET_CLASS = Collections.emptySet().getClass();
+    static final Class EMPTY_LIST_CLASS = Collections.emptyList().getClass();
+    static final Class SINGLETON_CLASS = Collections.singleton(0).getClass();
+    static final Class SINGLETON_LIST_CLASS = Collections.singletonList(0).getClass();
+    static final Class ARRAYS_LIST_CLASS = Arrays.asList(0).getClass();
+
+    static final Class UNMODIFIABLE_COLLECTION_CLASS = Collections.unmodifiableCollection(Collections.emptyList()).getClass();
+    static final Class UNMODIFIABLE_LIST_CLASS = Collections.unmodifiableList(Collections.emptyList()).getClass();
+    static final Class UNMODIFIABLE_SET_CLASS = Collections.unmodifiableSet(Collections.emptySet()).getClass();
+    static final Class UNMODIFIABLE_SORTED_SET_CLASS = Collections.unmodifiableSortedSet(Collections.emptySortedSet()).getClass();
+    static final Class UNMODIFIABLE_NAVIGABLE_SET_CLASS = Collections.unmodifiableNavigableSet(Collections.emptyNavigableSet()).getClass();
+
+    public static ListObjectReaderImpl INSTANCE = new ListObjectReaderImpl(ArrayList.class, ArrayList.class, ArrayList.class, Object.class, null);
+
+    final Type listGenericType;
+    final Class listImplementationClass;
+    final Class instanceClassType;
+    final long instanceHash;
+    final Type elementType;
+    final Class elementClass;
+    final String elementClassName;
+    final long classNameHash;
+    final Function factory;
+    ObjectReader elementReader;
+    volatile boolean hasInstanceError;
+
+    public static ObjectReader ofType(Type desiredType, Class listImplementationClass, long featureFlags) {
+        if (listImplementationClass == desiredType && "".equals(listImplementationClass.getSimpleName())) {
+            desiredType = listImplementationClass.getGenericSuperclass();
+            listImplementationClass = listImplementationClass.getSuperclass();
+        }
+
+        Type elementType = Object.class;
+        Type rawGenericType;
+        if (desiredType instanceof ParameterizedType) {
+            ParameterizedType paramType = (ParameterizedType) desiredType;
+            rawGenericType = paramType.getRawType();
+            Type[] typeArguments = paramType.getActualTypeArguments();
+            if (typeArguments.length == 1) {
+                elementType = typeArguments[0];
+            }
+        } else {
+            rawGenericType = desiredType;
+            if (listImplementationClass != null) {
+                Type parentType = listImplementationClass.getGenericSuperclass();
+                if (parentType instanceof ParameterizedType) {
+                    ParameterizedType paramType = (ParameterizedType) parentType;
+                    rawGenericType = paramType.getRawType();
+                    Type[] typeArguments = paramType.getActualTypeArguments();
+                    if (typeArguments.length == 1) {
+                        elementType = typeArguments[0];
+                    }
+                }
+            }
+        }
+
+        if (listImplementationClass == null) {
+            listImplementationClass = TypeUtils.getClass(rawGenericType);
+        }
+
+        Function factory = null;
+        Class concreteClass;
+
+        if (listImplementationClass == Iterable.class
+                || listImplementationClass == Collection.class
+                || listImplementationClass == List.class
+                || listImplementationClass == AbstractCollection.class
+                || listImplementationClass == AbstractList.class
+        ) {
+            concreteClass = ArrayList.class;
+        } else if (listImplementationClass == Queue.class
+                || listImplementationClass == Deque.class
+                || listImplementationClass == AbstractSequentialList.class) {
+            concreteClass = LinkedList.class;
+        } else if (listImplementationClass == Set.class || listImplementationClass == AbstractSet.class) {
+            concreteClass = HashSet.class;
+        } else if (listImplementationClass == EnumSet.class) {
+            concreteClass = HashSet.class;
+            factory = (element) -> EnumSet.copyOf((Collection) element);
+        } else if (listImplementationClass == NavigableSet.class || listImplementationClass == SortedSet.class) {
+            concreteClass = TreeSet.class;
+        } else if (listImplementationClass == SINGLETON_CLASS) {
+            concreteClass = ArrayList.class;
+            factory = (Object objectValue) -> Collections.singleton(((List) objectValue).get(0));
+        } else if (listImplementationClass == SINGLETON_LIST_CLASS) {
+            concreteClass = ArrayList.class;
+            factory = (Object objectValue) -> Collections.singletonList(((List) objectValue).get(0));
+        } else if (listImplementationClass == ARRAYS_LIST_CLASS) {
+            concreteClass = ArrayList.class;
+            factory = (Object objectValue) -> Arrays.asList(((List) objectValue).toArray());
+        } else if (listImplementationClass == UNMODIFIABLE_COLLECTION_CLASS) {
+            concreteClass = ArrayList.class;
+            factory = (Object objectValue) -> Collections.unmodifiableCollection((Collection) objectValue);
+        } else if (listImplementationClass == UNMODIFIABLE_LIST_CLASS) {
+            concreteClass = ArrayList.class;
+            factory = (Object objectValue) -> Collections.unmodifiableList((List) objectValue);
+        } else if (listImplementationClass == UNMODIFIABLE_SET_CLASS) {
+            concreteClass = LinkedHashSet.class;
+            factory = (Object objectValue) -> Collections.unmodifiableSet((Set) objectValue);
+        } else if (listImplementationClass == UNMODIFIABLE_SORTED_SET_CLASS) {
+            concreteClass = TreeSet.class;
+            factory = (Object objectValue) -> Collections.unmodifiableSortedSet((SortedSet) objectValue);
+        } else if (listImplementationClass == UNMODIFIABLE_NAVIGABLE_SET_CLASS) {
+            concreteClass = TreeSet.class;
+            factory = (Object objectValue) -> Collections.unmodifiableNavigableSet((NavigableSet) objectValue);
+        } else {
+            String resolvedTypeName = listImplementationClass.getTypeName();
+            switch (resolvedTypeName) {
+                case "com.google.common.collect.ImmutableList":
+                    concreteClass = ArrayList.class;
+                    factory = GuavaSupport.immutableListConverter();
+                    break;
+                case "com.google.common.collect.ImmutableSet":
+                    concreteClass = ArrayList.class;
+                    factory = GuavaSupport.immutableSetConverter();
+                    break;
+                case "com.google.common.collect.Lists$TransformingRandomAccessList":
+                    concreteClass = ArrayList.class;
+                    break;
+                case "com.google.common.collect.Lists.TransformingSequentialList":
+                    concreteClass = LinkedList.class;
+                    break;
+                default:
+                    concreteClass = listImplementationClass;
+                    break;
+            }
+        }
+
+        if (desiredType == ListObjectReaderImpl.EMPTY_SET_CLASS
+                || desiredType == ListObjectReaderImpl.EMPTY_LIST_CLASS
+                || desiredType == ListObjectReaderImpl.EMPTY_LIST_CLASS
+        ) {
+            return new ListObjectReaderImpl(desiredType, (Class) desiredType, (Class) desiredType, Object.class, null);
+        }
+
+        if (elementType == String.class && factory == null) {
+            return new ObjectReaderImplListStr(listImplementationClass, concreteClass);
+        }
+
+        if (elementType == Long.class && factory == null) {
+            return new ObjectReaderImplListInt64(listImplementationClass, concreteClass);
+        }
+
+        return new ListObjectReaderImpl(desiredType, listImplementationClass, concreteClass, elementType, factory);
+    }
+
+    public ListObjectReaderImpl(Type listGenericType, Class listImplementationClass, Class instanceClassType, Type elementType, Function factory) {
+        this.listGenericType = listGenericType;
+        this.listImplementationClass = listImplementationClass;
+        this.instanceClassType = instanceClassType;
+        this.instanceHash = Fnv.hashCode64(TypeUtils.getTypeName(instanceClassType));
+        this.elementType = elementType;
+        this.elementClass = TypeUtils.getClass(elementType);
+        this.factory = factory;
+        this.elementClassName = elementClass != null ? TypeUtils.getTypeName(elementClass) : null;
+        this.classNameHash = elementClassName != null ? Fnv.hashCode64(elementClassName) : 0;
+    }
+
+    @Override
+    public Class getObjectClass() {
+        return listImplementationClass;
+    }
+
+    @Override
+    public Function getBuildFunction() {
+        return factory;
+    }
+
+    @Override
+    public Object createInstance(Collection sourceCollection) {
+        int count = sourceCollection.size();
+
+        if (count == 0 && (listImplementationClass == List.class)) {
+            Collection resultList = Collections.emptyList();
+            if (factory != null) {
+                return factory.apply(resultList);
+            }
+            return resultList;
+        }
+
+        ObjectReaderProvider readerProvider = JSONFactory.getDefaultObjectReaderProvider();
+
+        Collection resultList = (Collection) createInstance(0L);
+        for (Object element : sourceCollection) {
+            if (element == null) {
+                resultList.add(null);
+                continue;
+            }
+
+            Object convertedValue = element;
+            Class<?> valueRuntimeClass = convertedValue.getClass();
+            if (valueRuntimeClass != elementType) {
+                Function conversionFunction = readerProvider.getTypeConvert(valueRuntimeClass, elementType);
+                if (conversionFunction != null) {
+                    convertedValue = conversionFunction.apply(convertedValue);
+                } else if (element instanceof Map) {
+                    Map resultMap = (Map) element;
+                    if (elementReader == null) {
+                        elementReader = readerProvider.getObjectReader(elementType);
+                    }
+                    convertedValue = elementReader.createInstance(resultMap, 0L);
+                } else if (convertedValue instanceof Collection) {
+                    if (elementReader == null) {
+                        elementReader = readerProvider.getObjectReader(elementType);
+                    }
+                    convertedValue = elementReader.createInstance((Collection) convertedValue);
+                } else if (elementClass.isInstance(convertedValue)) {
+                    // skip
+                } else {
+                    throw new JSONException("can not convert from " + valueRuntimeClass + " to " + elementType);
+                }
+            }
+            resultList.add(convertedValue);
+        }
+
+        if (factory != null) {
+            return factory.apply(resultList);
+        }
+
+        return resultList;
+    }
+
+    @Override
+    public Object createInstance(long featureFlags) {
+        if (instanceClassType == ArrayList.class) {
+            return JVM_VERSION == 8 ? new ArrayList(10) : new ArrayList();
+        }
+
+        if (instanceClassType == LinkedList.class) {
+            return new LinkedList();
+        }
+
+        if (instanceClassType == HashSet.class) {
+            return new HashSet();
+        }
+
+        if (instanceClassType == LinkedHashSet.class) {
+            return new LinkedHashSet();
+        }
+
+        if (instanceClassType == TreeSet.class) {
+            return new TreeSet();
+        }
+
+        if (instanceClassType == EMPTY_LIST_CLASS) {
+            return Collections.emptyList();
+        }
+
+        if (instanceClassType == EMPTY_SET_CLASS) {
+            return Collections.emptySet();
+        }
+
+        if (instanceClassType != null) {
+            JSONException jsonError = null;
+            if (!hasInstanceError) {
+                try {
+                    return instanceClassType.newInstance();
+                } catch (InstantiationException | IllegalAccessException instantiationEx) {
+                    hasInstanceError = true;
+                    jsonError = new JSONException("create list error, type " + instanceClassType);
+                }
+            }
+
+            if (hasInstanceError && List.class.isAssignableFrom(instanceClassType.getSuperclass())) {
+                try {
+                    return instanceClassType.getSuperclass().newInstance();
+                } catch (InstantiationException | IllegalAccessException instantiationEx) {
+                    hasInstanceError = true;
+                    jsonError = new JSONException("create list error, type " + instanceClassType);
+                }
+            }
+
+            if (jsonError != null) {
+                throw jsonError;
+            }
+        }
+
+        return new ArrayList();
+    }
+
+    @Override
+    public FieldReader getFieldReader(long fieldHash) {
+        return null;
+    }
+
+    @Override
+    public Object readJSONBObject(JSONReader reader, Type targetFieldType, Object fieldKey, long featureFlags) {
+        ObjectReader fieldReader = reader.checkAutoType(this.listImplementationClass, 0, featureFlags);
+
+        Function factory = this.factory;
+        Class listGenericType = this.instanceClassType;
+        if (fieldReader != null) {
+            listGenericType = fieldReader.getObjectClass();
+
+            if (listGenericType == UNMODIFIABLE_COLLECTION_CLASS) {
+                listGenericType = ArrayList.class;
+                factory = (Function<Collection, Collection>) Collections::unmodifiableCollection;
+            } else if (listGenericType == UNMODIFIABLE_LIST_CLASS) {
+                listGenericType = ArrayList.class;
+                factory = (Function<List, List>) Collections::unmodifiableList;
+            } else if (listGenericType == UNMODIFIABLE_SET_CLASS) {
+                listGenericType = LinkedHashSet.class;
+                factory = (Function<Set, Set>) Collections::unmodifiableSet;
+            } else if (listGenericType == UNMODIFIABLE_SORTED_SET_CLASS) {
+                listGenericType = TreeSet.class;
+                factory = (Function<SortedSet, SortedSet>) Collections::unmodifiableSortedSet;
+            } else if (listGenericType == UNMODIFIABLE_NAVIGABLE_SET_CLASS) {
+                listGenericType = TreeSet.class;
+                factory = (Function<NavigableSet, NavigableSet>) Collections::unmodifiableNavigableSet;
+            } else if (listGenericType == SINGLETON_CLASS) {
+                listGenericType = ArrayList.class;
+                factory = (Function<Collection, Collection>) ((Collection resultList) -> Collections.singleton(resultList.iterator().next()));
+            } else if (listGenericType == SINGLETON_LIST_CLASS) {
+                listGenericType = ArrayList.class;
+                factory = (Function<List, List>) ((List resultList) -> Collections.singletonList(resultList.get(0)));
+            }
+        }
+
+        int entryCount = reader.startArray();
+
+        if (entryCount > 0 && this.elementReader == null) {
+            this.elementReader = reader
+                    .getContext()
+                    .getObjectReader(this.elementType);
+        }
+
+        if (listGenericType == ARRAYS_LIST_CLASS) {
+            Object[] elements = new Object[entryCount];
+            List resultList = Arrays.asList(elements);
+            for (int index = 0; index < entryCount; ++index) {
+                Object element;
+
+                if (reader.isReference()) {
+                    String ref = reader.readReference();
+                    if ("..".equals(ref)) {
+                        element = resultList;
+                    } else {
+                        element = null;
+                        reader.addResolveTask((List) resultList, index, JSONPath.of(ref));
+                    }
+                } else {
+                    element = this.elementReader.readJSONBObject(reader, this.elementType, index, featureFlags);
+                }
+
+                elements[index] = element;
+            }
+            return resultList;
+        }
+
+        Collection resultList;
+        if (listGenericType == ArrayList.class) {
+            resultList = entryCount > 0 ? new ArrayList(entryCount) : new ArrayList();
+        } else if (listGenericType == JSONArray.class) {
+            resultList = entryCount > 0 ? new JSONArray(entryCount) : new JSONArray();
+        } else if (listGenericType == HashSet.class) {
+            resultList = new HashSet();
+        } else if (listGenericType == LinkedHashSet.class) {
+            resultList = new LinkedHashSet();
+        } else if (listGenericType == TreeSet.class) {
+            resultList = new TreeSet();
+        } else if (listGenericType == EMPTY_SET_CLASS) {
+            resultList = Collections.emptySet();
+        } else if (listGenericType == EMPTY_LIST_CLASS) {
+            resultList = Collections.emptyList();
+        } else if (listGenericType == SINGLETON_LIST_CLASS) {
+            resultList = new ArrayList();
+            factory = (Function<Collection, Collection>) ((Collection inputItems) -> Collections.singletonList(inputItems.iterator().next()));
+        } else if (listGenericType == UNMODIFIABLE_LIST_CLASS) {
+            resultList = new ArrayList();
+            factory = (Function<List, List>) ((List inputItems) -> Collections.unmodifiableList(inputItems));
+        } else if (listGenericType != null && listGenericType != this.listGenericType) {
+            try {
+                resultList = (Collection) listGenericType.newInstance();
+            } catch (InstantiationException | IllegalAccessException instantiationEx) {
+                throw new JSONException(reader.info("create instance error " + listGenericType), instantiationEx);
+            }
+        } else {
+            resultList = (Collection) createInstance(reader.getContext().getFeatures() | featureFlags);
+        }
+
+        ObjectReader elementReader = this.elementReader;
+        Type elementType = this.elementType;
+        if (targetFieldType != null && targetFieldType != listGenericType && targetFieldType instanceof ParameterizedType) {
+            Type[] typeArguments = ((ParameterizedType) targetFieldType).getActualTypeArguments();
+            if (typeArguments.length == 1) {
+                elementType = typeArguments[0];
+                if (elementType != this.elementType) {
+                    elementReader = reader.getObjectReader(elementType);
+                }
+            }
+        }
+
+        for (int index = 0; index < entryCount; ++index) {
+            Object element;
+
+            if (reader.isReference()) {
+                String ref = reader.readReference();
+                if ("..".equals(ref)) {
+                    element = resultList;
+                } else {
+                    reader.addResolveTask(resultList, index, JSONPath.of(ref));
+                    if (resultList instanceof List) {
+                        element = null;
+                    } else {
+                        continue;
+                    }
+                }
+            } else {
+                ObjectReader autoReader = reader.checkAutoType(elementClass, classNameHash, featureFlags);
+                if (autoReader != null) {
+                    element = autoReader.readJSONBObject(reader, elementType, index, featureFlags);
+                } else {
+                    element = elementReader.readJSONBObject(reader, elementType, index, featureFlags);
+                }
+            }
+
+            resultList.add(element);
+        }
+
+        if (factory != null) {
+            return factory.apply(resultList);
+        }
+
+        return resultList;
+    }
+
+    @Override
+    public Object readObject(JSONReader reader, Type targetFieldType, Object fieldKey, long featureFlags) {
+        JSONReader.Context parseContext = reader.getContext();
+        if (this.elementReader == null) {
+            this.elementReader = parseContext
+                    .getObjectReader(this.elementType);
+        }
+
+        if (reader.isJSONB()) {
+            return readJSONBObject(reader, targetFieldType, fieldKey, 0);
+        }
+
+        if (reader.readIfNull()) {
+            return null;
+        }
+
+        Collection resultList;
+        if (reader.nextIfSet()) {
+            resultList = new HashSet();
+        } else {
+            resultList = (Collection) createInstance(parseContext.getFeatures() | featureFlags);
+        }
+        char currentChar = reader.current();
+        if (currentChar == '"') {
+            String text = reader.readString();
+            if (elementClass == String.class) {
+                reader.nextIfMatch(',');
+                resultList.add(text);
+                return resultList;
+            }
+
+            if (text.isEmpty()) {
+                reader.nextIfMatch(',');
+                return null;
+            }
+
+            Function conversionFunction = parseContext.getProvider().getTypeConvert(String.class, this.elementType);
+            if (conversionFunction != null) {
+                Object convertedValue = conversionFunction.apply(text);
+                reader.nextIfMatch(',');
+                resultList.add(convertedValue);
+                return resultList;
+            }
+            throw new JSONException(reader.info());
+        }
+
+        if (!reader.nextIfMatch('[')) {
+            if ((elementClass != Object.class && this.elementReader != null) || (elementClass == Object.class && reader.isObject())) {
+                Object element = this.elementReader.readObject(reader, this.elementType, 0, 0);
+                resultList.add(element);
+                if (factory != null) {
+                    resultList = (Collection) factory.apply(resultList);
+                }
+                return resultList;
+            }
+
+            throw new JSONException(reader.info());
+        }
+
+        ObjectReader elementReader = this.elementReader;
+        Type elementType = this.elementType;
+        if (targetFieldType != null && targetFieldType != listGenericType && targetFieldType instanceof ParameterizedType) {
+            Type[] typeArguments = ((ParameterizedType) targetFieldType).getActualTypeArguments();
+            if (typeArguments.length == 1) {
+                elementType = typeArguments[0];
+                if (elementType != this.elementType) {
+                    elementReader = reader.getObjectReader(elementType);
+                }
+            }
+        }
+
+        for (int index = 0; ; ++index) {
+            if (reader.nextIfMatch(']')) {
+                break;
+            }
+
+            Object element;
+            if (elementType == String.class) {
+                element = reader.readString();
+            } else if (elementReader != null) {
+                if (reader.isReference()) {
+                    String ref = reader.readReference();
+                    if ("..".equals(ref)) {
+                        element = this;
+                    } else {
+                        reader.addResolveTask(resultList, index, JSONPath.of(ref));
+                        continue;
+                    }
+                } else {
+                    element = elementReader.readObject(reader, elementType, index, 0);
+                }
+            } else {
+                throw new JSONException(reader.info("TODO : " + elementType));
+            }
+
+            resultList.add(element);
+
+            if (reader.nextIfMatch(',')) {
+                continue;
+            }
+        }
+
+        reader.nextIfMatch(',');
+
+        if (factory != null) {
+            return factory.apply(resultList);
+        }
+
+        return resultList;
+    }
+}
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderBaseModule.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderBaseModule.java
index 9e292fb36..345b5a827 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderBaseModule.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderBaseModule.java
@@ -1793,7 +1793,7 @@ public class ObjectReaderBaseModule
                 || type == AbstractList.class
                 || type == ArrayList.class
         ) {
-            return ObjectReaderImplList.of(type, null, 0);
+            return ListObjectReaderImpl.ofType(type, null, 0);
             // return new ObjectReaderImplList(type, (Class) type, ArrayList.class, Object.class, null);
         }
 
@@ -1802,17 +1802,17 @@ public class ObjectReaderBaseModule
                 || type == AbstractSequentialList.class
                 || type == LinkedList.class) {
 //            return new ObjectReaderImplList(type, (Class) type, LinkedList.class, Object.class, null);
-            return ObjectReaderImplList.of(type, null, 0);
+            return ListObjectReaderImpl.ofType(type, null, 0);
         }
 
         if (type == Set.class || type == AbstractSet.class || type == EnumSet.class) {
 //            return new ObjectReaderImplList(type, (Class) type, HashSet.class, Object.class, null);
-            return ObjectReaderImplList.of(type, null, 0);
+            return ListObjectReaderImpl.ofType(type, null, 0);
         }
 
         if (type == NavigableSet.class || type == SortedSet.class) {
 //            return new ObjectReaderImplList(type, (Class) type, TreeSet.class, Object.class, null);
-            return ObjectReaderImplList.of(type, null, 0);
+            return ListObjectReaderImpl.ofType(type, null, 0);
         }
 
         if (type == ConcurrentLinkedDeque.class
@@ -1824,27 +1824,27 @@ public class ObjectReaderBaseModule
                 || type == CopyOnWriteArrayList.class
         ) {
 //            return new ObjectReaderImplList(type, (Class) type, (Class) type, Object.class, null);
-            return ObjectReaderImplList.of(type, null, 0);
-        }
-
-        if (type == ObjectReaderImplList.CLASS_EMPTY_SET
-                || type == ObjectReaderImplList.CLASS_EMPTY_LIST
-                || type == ObjectReaderImplList.CLASS_SINGLETON
-                || type == ObjectReaderImplList.CLASS_SINGLETON_LIST
-                || type == ObjectReaderImplList.CLASS_ARRAYS_LIST
-                || type == ObjectReaderImplList.CLASS_UNMODIFIABLE_COLLECTION
-                || type == ObjectReaderImplList.CLASS_UNMODIFIABLE_LIST
-                || type == ObjectReaderImplList.CLASS_UNMODIFIABLE_SET
-                || type == ObjectReaderImplList.CLASS_UNMODIFIABLE_SORTED_SET
-                || type == ObjectReaderImplList.CLASS_UNMODIFIABLE_NAVIGABLE_SET
+            return ListObjectReaderImpl.ofType(type, null, 0);
+        }
+
+        if (type == ListObjectReaderImpl.EMPTY_SET_CLASS
+                || type == ListObjectReaderImpl.EMPTY_LIST_CLASS
+                || type == ListObjectReaderImpl.SINGLETON_CLASS
+                || type == ListObjectReaderImpl.SINGLETON_LIST_CLASS
+                || type == ListObjectReaderImpl.ARRAYS_LIST_CLASS
+                || type == ListObjectReaderImpl.UNMODIFIABLE_COLLECTION_CLASS
+                || type == ListObjectReaderImpl.UNMODIFIABLE_LIST_CLASS
+                || type == ListObjectReaderImpl.UNMODIFIABLE_SET_CLASS
+                || type == ListObjectReaderImpl.UNMODIFIABLE_SORTED_SET_CLASS
+                || type == ListObjectReaderImpl.UNMODIFIABLE_NAVIGABLE_SET_CLASS
         ) {
 //            return new ObjectReaderImplList(type, (Class) type, (Class) type, Object.class, null);
-            return ObjectReaderImplList.of(type, null, 0);
+            return ListObjectReaderImpl.ofType(type, null, 0);
         }
 
         if (type == TypeUtils.CLASS_SINGLE_SET) {
 //            return SingletonSetImpl.INSTANCE;
-            return ObjectReaderImplList.of(type, null, 0);
+            return ListObjectReaderImpl.ofType(type, null, 0);
         }
 
         if (type == Object.class
@@ -1867,7 +1867,7 @@ public class ObjectReaderBaseModule
             }
 
             if (List.class.isAssignableFrom(objectClass)) {
-                return ObjectReaderImplList.of(objectClass, objectClass, 0);
+                return ListObjectReaderImpl.ofType(objectClass, objectClass, 0);
             }
 
             if (objectClass.isArray()) {
@@ -1978,7 +1978,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, ArrayList.class);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -1991,7 +1991,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, LinkedList.class);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -2001,7 +2001,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, HashSet.class);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -2011,7 +2011,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, TreeSet.class);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -2028,15 +2028,15 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, (Class) rawType);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
                 switch (rawType.getTypeName()) {
                     case "com.google.common.collect.ImmutableList":
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     case "com.google.common.collect.ImmutableSet":
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     default:
                         break;
                 }
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
deleted file mode 100644
index f4808b2b7..000000000
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
+++ /dev/null
@@ -1,553 +0,3 @@
-package com.alibaba.fastjson2.reader;
 
 import com.alibaba.fastjson2.*;
-import com.alibaba.fastjson2.util.Fnv;
-import com.alibaba.fastjson2.util.GuavaSupport;
-import com.alibaba.fastjson2.util.TypeUtils;
-
-import java.lang.reflect.ParameterizedType;
-import java.lang.reflect.Type;
 import java.util.*;
-import java.util.function.Function;
-
-import static com.alibaba.fastjson2.util.JDKUtils.JVM_VERSION;
-
-public final class ObjectReaderImplList
-        implements ObjectReader {
-    static final Class CLASS_EMPTY_SET = Collections.emptySet().getClass();
-    static final Class CLASS_EMPTY_LIST = Collections.emptyList().getClass();
-    static final Class CLASS_SINGLETON = Collections.singleton(0).getClass();
-    static final Class CLASS_SINGLETON_LIST = Collections.singletonList(0).getClass();
-    static final Class CLASS_ARRAYS_LIST = Arrays.asList(0).getClass();
-
-    static final Class CLASS_UNMODIFIABLE_COLLECTION = Collections.unmodifiableCollection(Collections.emptyList()).getClass();
-    static final Class CLASS_UNMODIFIABLE_LIST = Collections.unmodifiableList(Collections.emptyList()).getClass();
-    static final Class CLASS_UNMODIFIABLE_SET = Collections.unmodifiableSet(Collections.emptySet()).getClass();
-    static final Class CLASS_UNMODIFIABLE_SORTED_SET = Collections.unmodifiableSortedSet(Collections.emptySortedSet()).getClass();
-    static final Class CLASS_UNMODIFIABLE_NAVIGABLE_SET = Collections.unmodifiableNavigableSet(Collections.emptyNavigableSet()).getClass();
-
-    public static ObjectReaderImplList INSTANCE = new ObjectReaderImplList(ArrayList.class, ArrayList.class, ArrayList.class, Object.class, null);
-
-    final Type listType;
-    final Class listClass;
-    final Class instanceType;
-    final long instanceTypeHash;
-    final Type itemType;
-    final Class itemClass;
-    final String itemClassName;
-    final long itemClassNameHash;
-    final Function builder;
-    ObjectReader itemObjectReader;
-    volatile boolean instanceError;
-
-    public static ObjectReader of(Type type, Class listClass, long features) {
-        if (listClass == type && "".equals(listClass.getSimpleName())) {
-            type = listClass.getGenericSuperclass();
-            listClass = listClass.getSuperclass();
-        }
-
-        Type itemType = Object.class;
-        Type rawType;
-        if (type instanceof ParameterizedType) {
-            ParameterizedType parameterizedType = (ParameterizedType) type;
-            rawType = parameterizedType.getRawType();
-            Type[] actualTypeArguments = parameterizedType.getActualTypeArguments();
-            if (actualTypeArguments.length == 1) {
-                itemType = actualTypeArguments[0];
-            }
-        } else {
-            rawType = type;
-            if (listClass != null) {
-                Type superType = listClass.getGenericSuperclass();
-                if (superType instanceof ParameterizedType) {
-                    ParameterizedType parameterizedType = (ParameterizedType) superType;
-                    rawType = parameterizedType.getRawType();
-                    Type[] actualTypeArguments = parameterizedType.getActualTypeArguments();
-                    if (actualTypeArguments.length == 1) {
-                        itemType = actualTypeArguments[0];
-                    }
-                }
-            }
-        }
-
-        if (listClass == null) {
-            listClass = TypeUtils.getClass(rawType);
-        }
-
-        Function builder = null;
-        Class instanceClass;
-
-        if (listClass == Iterable.class
-                || listClass == Collection.class
-                || listClass == List.class
-                || listClass == AbstractCollection.class
-                || listClass == AbstractList.class
-        ) {
-            instanceClass = ArrayList.class;
-        } else if (listClass == Queue.class
-                || listClass == Deque.class
-                || listClass == AbstractSequentialList.class) {
-            instanceClass = LinkedList.class;
-        } else if (listClass == Set.class || listClass == AbstractSet.class) {
-            instanceClass = HashSet.class;
-        } else if (listClass == EnumSet.class) {
-            instanceClass = HashSet.class;
-            builder = (o) -> EnumSet.copyOf((Collection) o);
-        } else if (listClass == NavigableSet.class || listClass == SortedSet.class) {
-            instanceClass = TreeSet.class;
-        } else if (listClass == CLASS_SINGLETON) {
-            instanceClass = ArrayList.class;
-            builder = (Object obj) -> Collections.singleton(((List) obj).get(0));
-        } else if (listClass == CLASS_SINGLETON_LIST) {
-            instanceClass = ArrayList.class;
-            builder = (Object obj) -> Collections.singletonList(((List) obj).get(0));
-        } else if (listClass == CLASS_ARRAYS_LIST) {
-            instanceClass = ArrayList.class;
-            builder = (Object obj) -> Arrays.asList(((List) obj).toArray());
-        } else if (listClass == CLASS_UNMODIFIABLE_COLLECTION) {
-            instanceClass = ArrayList.class;
-            builder = (Object obj) -> Collections.unmodifiableCollection((Collection) obj);
-        } else if (listClass == CLASS_UNMODIFIABLE_LIST) {
-            instanceClass = ArrayList.class;
-            builder = (Object obj) -> Collections.unmodifiableList((List) obj);
-        } else if (listClass == CLASS_UNMODIFIABLE_SET) {
-            instanceClass = LinkedHashSet.class;
-            builder = (Object obj) -> Collections.unmodifiableSet((Set) obj);
-        } else if (listClass == CLASS_UNMODIFIABLE_SORTED_SET) {
-            instanceClass = TreeSet.class;
-            builder = (Object obj) -> Collections.unmodifiableSortedSet((SortedSet) obj);
-        } else if (listClass == CLASS_UNMODIFIABLE_NAVIGABLE_SET) {
-            instanceClass = TreeSet.class;
-            builder = (Object obj) -> Collections.unmodifiableNavigableSet((NavigableSet) obj);
-        } else {
-            String typeName = listClass.getTypeName();
-            switch (typeName) {
-                case "com.google.common.collect.ImmutableList":
-                    instanceClass = ArrayList.class;
-                    builder = GuavaSupport.immutableListConverter();
-                    break;
-                case "com.google.common.collect.ImmutableSet":
-                    instanceClass = ArrayList.class;
-                    builder = GuavaSupport.immutableSetConverter();
-                    break;
-                case "com.google.common.collect.Lists$TransformingRandomAccessList":
-                    instanceClass = ArrayList.class;
-                    break;
-                case "com.google.common.collect.Lists.TransformingSequentialList":
-                    instanceClass = LinkedList.class;
-                    break;
-                default:
-                    instanceClass = listClass;
-                    break;
-            }
-        }
-
-        if (type == ObjectReaderImplList.CLASS_EMPTY_SET
-                || type == ObjectReaderImplList.CLASS_EMPTY_LIST
-                || type == ObjectReaderImplList.CLASS_EMPTY_LIST
-        ) {
-            return new ObjectReaderImplList(type, (Class) type, (Class) type, Object.class, null);
-        }
-
-        if (itemType == String.class && builder == null) {
-            return new ObjectReaderImplListStr(listClass, instanceClass);
-        }
-
-        if (itemType == Long.class && builder == null) {
-            return new ObjectReaderImplListInt64(listClass, instanceClass);
-        }
-
-        return new ObjectReaderImplList(type, listClass, instanceClass, itemType, builder);
-    }
-
-    public ObjectReaderImplList(Type listType, Class listClass, Class instanceType, Type itemType, Function builder) {
-        this.listType = listType;
-        this.listClass = listClass;
-        this.instanceType = instanceType;
-        this.instanceTypeHash = Fnv.hashCode64(TypeUtils.getTypeName(instanceType));
-        this.itemType = itemType;
-        this.itemClass = TypeUtils.getClass(itemType);
-        this.builder = builder;
-        this.itemClassName = itemClass != null ? TypeUtils.getTypeName(itemClass) : null;
-        this.itemClassNameHash = itemClassName != null ? Fnv.hashCode64(itemClassName) : 0;
-    }
-
-    @Override
-    public Class getObjectClass() {
-        return listClass;
-    }
-
-    @Override
-    public Function getBuildFunction() {
-        return builder;
-    }
-
-    @Override
-    public Object createInstance(Collection collection) {
-        int size = collection.size();
-
-        if (size == 0 && (listClass == List.class)) {
-            Collection list = Collections.emptyList();
-            if (builder != null) {
-                return builder.apply(list);
-            }
-            return list;
-        }
-
-        ObjectReaderProvider provider = JSONFactory.getDefaultObjectReaderProvider();
-
-        Collection list = (Collection) createInstance(0L);
-        for (Object item : collection) {
-            if (item == null) {
-                list.add(null);
-                continue;
-            }
-
-            Object value = item;
-            Class<?> valueClass = value.getClass();
-            if (valueClass != itemType) {
-                Function typeConvert = provider.getTypeConvert(valueClass, itemType);
-                if (typeConvert != null) {
-                    value = typeConvert.apply(value);
-                } else if (item instanceof Map) {
-                    Map map = (Map) item;
-                    if (itemObjectReader == null) {
-                        itemObjectReader = provider.getObjectReader(itemType);
-                    }
-                    value = itemObjectReader.createInstance(map, 0L);
-                } else if (value instanceof Collection) {
-                    if (itemObjectReader == null) {
-                        itemObjectReader = provider.getObjectReader(itemType);
-                    }
-                    value = itemObjectReader.createInstance((Collection) value);
-                } else if (itemClass.isInstance(value)) {
-                    // skip
-                } else {
-                    throw new JSONException("can not convert from " + valueClass + " to " + itemType);
-                }
-            }
-            list.add(value);
-        }
-
-        if (builder != null) {
-            return builder.apply(list);
-        }
-
-        return list;
-    }
-
-    @Override
-    public Object createInstance(long features) {
-        if (instanceType == ArrayList.class) {
-            return JVM_VERSION == 8 ? new ArrayList(10) : new ArrayList();
-        }
-
-        if (instanceType == LinkedList.class) {
-            return new LinkedList();
-        }
-
-        if (instanceType == HashSet.class) {
-            return new HashSet();
-        }
-
-        if (instanceType == LinkedHashSet.class) {
-            return new LinkedHashSet();
-        }
-
-        if (instanceType == TreeSet.class) {
-            return new TreeSet();
-        }
-
-        if (instanceType == CLASS_EMPTY_LIST) {
-            return Collections.emptyList();
-        }
-
-        if (instanceType == CLASS_EMPTY_SET) {
-            return Collections.emptySet();
-        }
-
-        if (instanceType != null) {
-            JSONException error = null;
-            if (!instanceError) {
-                try {
-                    return instanceType.newInstance();
-                } catch (InstantiationException | IllegalAccessException e) {
-                    instanceError = true;
-                    error = new JSONException("create list error, type " + instanceType);
-                }
-            }
-
-            if (instanceError && List.class.isAssignableFrom(instanceType.getSuperclass())) {
-                try {
-                    return instanceType.getSuperclass().newInstance();
-                } catch (InstantiationException | IllegalAccessException e) {
-                    instanceError = true;
-                    error = new JSONException("create list error, type " + instanceType);
-                }
-            }
-
-            if (error != null) {
-                throw error;
-            }
-        }
-
-        return new ArrayList();
-    }
-
-    @Override
-    public FieldReader getFieldReader(long hashCode) {
-        return null;
-    }
-
-    @Override
-    public Object readJSONBObject(JSONReader jsonReader, Type fieldType, Object fieldName, long features) {
-        ObjectReader objectReader = jsonReader.checkAutoType(this.listClass, 0, features);
-
-        Function builder = this.builder;
-        Class listType = this.instanceType;
-        if (objectReader != null) {
-            listType = objectReader.getObjectClass();
-
-            if (listType == CLASS_UNMODIFIABLE_COLLECTION) {
-                listType = ArrayList.class;
-                builder = (Function<Collection, Collection>) Collections::unmodifiableCollection;
-            } else if (listType == CLASS_UNMODIFIABLE_LIST) {
-                listType = ArrayList.class;
-                builder = (Function<List, List>) Collections::unmodifiableList;
-            } else if (listType == CLASS_UNMODIFIABLE_SET) {
-                listType = LinkedHashSet.class;
-                builder = (Function<Set, Set>) Collections::unmodifiableSet;
-            } else if (listType == CLASS_UNMODIFIABLE_SORTED_SET) {
-                listType = TreeSet.class;
-                builder = (Function<SortedSet, SortedSet>) Collections::unmodifiableSortedSet;
-            } else if (listType == CLASS_UNMODIFIABLE_NAVIGABLE_SET) {
-                listType = TreeSet.class;
-                builder = (Function<NavigableSet, NavigableSet>) Collections::unmodifiableNavigableSet;
-            } else if (listType == CLASS_SINGLETON) {
-                listType = ArrayList.class;
-                builder = (Function<Collection, Collection>) ((Collection list) -> Collections.singleton(list.iterator().next()));
-            } else if (listType == CLASS_SINGLETON_LIST) {
-                listType = ArrayList.class;
-                builder = (Function<List, List>) ((List list) -> Collections.singletonList(list.get(0)));
-            }
-        }
-
-        int entryCnt = jsonReader.startArray();
-
-        if (entryCnt > 0 && itemObjectReader == null) {
-            itemObjectReader = jsonReader
-                    .getContext()
-                    .getObjectReader(itemType);
-        }
-
-        if (listType == CLASS_ARRAYS_LIST) {
-            Object[] array = new Object[entryCnt];
-            List list = Arrays.asList(array);
-            for (int i = 0; i < entryCnt; ++i) {
-                Object item;
-
-                if (jsonReader.isReference()) {
-                    String reference = jsonReader.readReference();
-                    if ("..".equals(reference)) {
-                        item = list;
-                    } else {
-                        item = null;
-                        jsonReader.addResolveTask((List) list, i, JSONPath.of(reference));
-                    }
-                } else {
-                    item = itemObjectReader.readJSONBObject(jsonReader, itemType, i, features);
-                }
-
-                array[i] = item;
-            }
-            return list;
-        }
-
-        Collection list;
-        if (listType == ArrayList.class) {
-            list = entryCnt > 0 ? new ArrayList(entryCnt) : new ArrayList();
-        } else if (listType == JSONArray.class) {
-            list = entryCnt > 0 ? new JSONArray(entryCnt) : new JSONArray();
-        } else if (listType == HashSet.class) {
-            list = new HashSet();
-        } else if (listType == LinkedHashSet.class) {
-            list = new LinkedHashSet();
-        } else if (listType == TreeSet.class) {
-            list = new TreeSet();
-        } else if (listType == CLASS_EMPTY_SET) {
-            list = Collections.emptySet();
-        } else if (listType == CLASS_EMPTY_LIST) {
-            list = Collections.emptyList();
-        } else if (listType == CLASS_SINGLETON_LIST) {
-            list = new ArrayList();
-            builder = (Function<Collection, Collection>) ((Collection items) -> Collections.singletonList(items.iterator().next()));
-        } else if (listType == CLASS_UNMODIFIABLE_LIST) {
-            list = new ArrayList();
-            builder = (Function<List, List>) ((List items) -> Collections.unmodifiableList(items));
-        } else if (listType != null && listType != this.listType) {
-            try {
-                list = (Collection) listType.newInstance();
-            } catch (InstantiationException | IllegalAccessException e) {
-                throw new JSONException(jsonReader.info("create instance error " + listType), e);
-            }
-        } else {
-            list = (Collection) createInstance(jsonReader.getContext().getFeatures() | features);
-        }
-
-        ObjectReader itemObjectReader = this.itemObjectReader;
-        Type itemType = this.itemType;
-        if (fieldType != null && fieldType != listType && fieldType instanceof ParameterizedType) {
-            Type[] actualTypeArguments = ((ParameterizedType) fieldType).getActualTypeArguments();
-            if (actualTypeArguments.length == 1) {
-                itemType = actualTypeArguments[0];
-                if (itemType != this.itemType) {
-                    itemObjectReader = jsonReader.getObjectReader(itemType);
-                }
-            }
-        }
-
-        for (int i = 0; i < entryCnt; ++i) {
-            Object item;
-
-            if (jsonReader.isReference()) {
-                String reference = jsonReader.readReference();
-                if ("..".equals(reference)) {
-                    item = list;
-                } else {
-                    jsonReader.addResolveTask(list, i, JSONPath.of(reference));
-                    if (list instanceof List) {
-                        item = null;
-                    } else {
-                        continue;
-                    }
-                }
-            } else {
-                ObjectReader autoTypeReader = jsonReader.checkAutoType(itemClass, itemClassNameHash, features);
-                if (autoTypeReader != null) {
-                    item = autoTypeReader.readJSONBObject(jsonReader, itemType, i, features);
-                } else {
-                    item = itemObjectReader.readJSONBObject(jsonReader, itemType, i, features);
-                }
-            }
-
-            list.add(item);
-        }
-
-        if (builder != null) {
-            return builder.apply(list);
-        }
-
-        return list;
-    }
-
-    @Override
-    public Object readObject(JSONReader jsonReader, Type fieldType, Object fieldName, long features) {
-        JSONReader.Context context = jsonReader.getContext();
-        if (itemObjectReader == null) {
-            itemObjectReader = context
-                    .getObjectReader(itemType);
-        }
-
-        if (jsonReader.isJSONB()) {
-            return readJSONBObject(jsonReader, fieldType, fieldName, 0);
-        }
-
-        if (jsonReader.readIfNull()) {
-            return null;
-        }
-
-        Collection list;
-        if (jsonReader.nextIfSet()) {
-            list = new HashSet();
-        } else {
-            list = (Collection) createInstance(context.getFeatures() | features);
-        }
-        char ch = jsonReader.current();
-        if (ch == '"') {
-            String str = jsonReader.readString();
-            if (itemClass == String.class) {
-                jsonReader.nextIfMatch(',');
-                list.add(str);
-                return list;
-            }
-
-            if (str.isEmpty()) {
-                jsonReader.nextIfMatch(',');
-                return null;
-            }
-
-            Function typeConvert = context.getProvider().getTypeConvert(String.class, itemType);
-            if (typeConvert != null) {
-                Object converted = typeConvert.apply(str);
-                jsonReader.nextIfMatch(',');
-                list.add(converted);
-                return list;
-            }
-            throw new JSONException(jsonReader.info());
-        }
-
-        if (!jsonReader.nextIfMatch('[')) {
-            if ((itemClass != Object.class && itemObjectReader != null) || (itemClass == Object.class && jsonReader.isObject())) {
-                Object item = itemObjectReader.readObject(jsonReader, itemType, 0, 0);
-                list.add(item);
-                if (builder != null) {
-                    list = (Collection) builder.apply(list);
-                }
-                return list;
-            }
-
-            throw new JSONException(jsonReader.info());
-        }
-
-        ObjectReader itemObjectReader = this.itemObjectReader;
-        Type itemType = this.itemType;
-        if (fieldType != null && fieldType != listType && fieldType instanceof ParameterizedType) {
-            Type[] actualTypeArguments = ((ParameterizedType) fieldType).getActualTypeArguments();
-            if (actualTypeArguments.length == 1) {
-                itemType = actualTypeArguments[0];
-                if (itemType != this.itemType) {
-                    itemObjectReader = jsonReader.getObjectReader(itemType);
-                }
-            }
-        }
-
-        for (int i = 0; ; ++i) {
-            if (jsonReader.nextIfMatch(']')) {
-                break;
-            }
-
-            Object item;
-            if (itemType == String.class) {
-                item = jsonReader.readString();
-            } else if (itemObjectReader != null) {
-                if (jsonReader.isReference()) {
-                    String reference = jsonReader.readReference();
-                    if ("..".equals(reference)) {
-                        item = this;
-                    } else {
-                        jsonReader.addResolveTask(list, i, JSONPath.of(reference));
-                        continue;
-                    }
-                } else {
-                    item = itemObjectReader.readObject(jsonReader, itemType, i, 0);
-                }
-            } else {
-                throw new JSONException(jsonReader.info("TODO : " + itemType));
-            }
-
-            list.add(item);
-
-            if (jsonReader.nextIfMatch(',')) {
-                continue;
-            }
-        }
-
-        jsonReader.nextIfMatch(',');
-
-        if (builder != null) {
-            return builder.apply(list);
-        }
-
-        return list;
-    }
-}
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplListStr.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplListStr.java
index e1b8dd2d9..c0e6a4d9d 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplListStr.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplListStr.java
@@ -9,7 +9,8 @@ import java.lang.reflect.Type;
 import java.util.*;
 import java.util.function.Function;
 
 import static com.alibaba.fastjson2.reader.ObjectReaderImplList.*;
+import static com.alibaba.fastjson2.reader.ListObjectReaderImpl.*;
 
 public final class ObjectReaderImplListStr
         implements ObjectReader {
@@ -89,7 +90,7 @@ public final class ObjectReaderImplListStr
             instanceType = objectReader.getObjectClass();
         }
 
-        if (instanceType == CLASS_ARRAYS_LIST) {
+        if (instanceType == ARRAYS_LIST_CLASS) {
             int entryCnt = jsonReader.startArray();
             String[] array = new String[entryCnt];
             for (int i = 0; i < entryCnt; ++i) {
@@ -106,25 +107,25 @@ public final class ObjectReaderImplListStr
             list = entryCnt > 0 ? new ArrayList(entryCnt) : new ArrayList();
         } else if (instanceType == JSONArray.class) {
             list = entryCnt > 0 ? new JSONArray(entryCnt) : new JSONArray();
-        } else if (instanceType == CLASS_UNMODIFIABLE_COLLECTION) {
+        } else if (instanceType == UNMODIFIABLE_COLLECTION_CLASS) {
             list = new ArrayList();
             builder = (Function<Collection, Collection>) Collections::unmodifiableCollection;
-        } else if (instanceType == CLASS_UNMODIFIABLE_LIST) {
+        } else if (instanceType == UNMODIFIABLE_LIST_CLASS) {
             list = new ArrayList();
             builder = (Function<List, List>) Collections::unmodifiableList;
-        } else if (instanceType == CLASS_UNMODIFIABLE_SET) {
+        } else if (instanceType == UNMODIFIABLE_SET_CLASS) {
             list = new LinkedHashSet();
             builder = (Function<Set, Set>) Collections::unmodifiableSet;
-        } else if (instanceType == CLASS_UNMODIFIABLE_SORTED_SET) {
+        } else if (instanceType == UNMODIFIABLE_SORTED_SET_CLASS) {
             list = new TreeSet();
             builder = (Function<SortedSet, SortedSet>) Collections::unmodifiableSortedSet;
-        } else if (instanceType == CLASS_UNMODIFIABLE_NAVIGABLE_SET) {
+        } else if (instanceType == UNMODIFIABLE_NAVIGABLE_SET_CLASS) {
             list = new TreeSet();
             builder = (Function<NavigableSet, NavigableSet>) Collections::unmodifiableNavigableSet;
-        } else if (instanceType == CLASS_SINGLETON) {
+        } else if (instanceType == SINGLETON_CLASS) {
             list = new ArrayList();
             builder = (Function<Collection, Collection>) ((Collection collection) -> Collections.singleton(collection.iterator().next()));
-        } else if (instanceType == CLASS_SINGLETON_LIST) {
+        } else if (instanceType == SINGLETON_LIST_CLASS) {
             list = new ArrayList();
             builder = (Function<Collection, Collection>) ((Collection collection) -> Collections.singletonList(collection.iterator().next()));
         } else if (instanceType != null && instanceType != this.listType) {
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java
index 5721d452c..ebc06de16 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java
@@ -523,9 +523,9 @@ public class ObjectReaderProvider
             if (keyClass != null && keyClass.getClassLoader() == classLoader) {
                 return true;
             }
-        } else if (objectReader instanceof ObjectReaderImplList) {
-            ObjectReaderImplList list = (ObjectReaderImplList) objectReader;
-            if (list.itemClass != null && list.itemClass.getClassLoader() == classLoader) {
+        } else if (objectReader instanceof ListObjectReaderImpl) {
+            ListObjectReaderImpl list = (ListObjectReaderImpl) objectReader;
+            if (list.elementClass != null && list.elementClass.getClassLoader() == classLoader) {
                 return true;
             }
         } else if (objectReader instanceof ObjectReaderImplOptional) {
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONTest.java b/core/src/test/java/com/alibaba/fastjson2/JSONTest.java
index 14acf263b..71959915e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONTest.java
@@ -6,7 +6,7 @@ import com.alibaba.fastjson2.filter.PascalNameFilter;
 import com.alibaba.fastjson2.filter.SimplePropertyPreFilter;
 import com.alibaba.fastjson2.modules.ObjectReaderModule;
 import com.alibaba.fastjson2.modules.ObjectWriterModule;
-import com.alibaba.fastjson2.reader.ObjectReaderImplList;
+import com.alibaba.fastjson2.reader.ListObjectReaderImpl;
 import com.alibaba.fastjson2.reader.ObjectReaderImplListStr;
 import com.alibaba.fastjson2.reader.ObjectReaderProvider;
 import com.alibaba.fastjson2.util.Fnv;
@@ -763,9 +763,9 @@ public class JSONTest {
 
     @Test
     public void test_list_0() {
-        assertNull(ObjectReaderImplList.INSTANCE.getFieldReader(0));
-        ObjectReaderImplList.INSTANCE.getObjectClass();
-        assertEquals(Fnv.hashCode64("@type"), ObjectReaderImplList.INSTANCE.getTypeKeyHash());
+        assertNull(ListObjectReaderImpl.INSTANCE.getFieldReader(0));
+        ListObjectReaderImpl.INSTANCE.getObjectClass();
+        assertEquals(Fnv.hashCode64("@type"), ListObjectReaderImpl.INSTANCE.getTypeKeyHash());
 
         assertEquals(123,
                 ((List) JSON.parseObject("\"123\"",
@@ -784,9 +784,9 @@ public class JSONTest {
                         new TypeReference<AbstractList<Integer>>() {}.getType()))
                         .get(0));
 
-        new ObjectReaderImplList(MyList.class, MyList.class, MyList.class, Integer.class, null).createInstance();
+        new ListObjectReaderImpl(MyList.class, MyList.class, MyList.class, Integer.class, null).createInstance();
 
-        Object instance = new ObjectReaderImplList(MyList0.class, MyList0.class, MyList0.class, Integer.class, null).createInstance();
+        Object instance = new ListObjectReaderImpl(MyList0.class, MyList0.class, MyList0.class, Integer.class, null).createInstance();
         assertNotNull(instance);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeFilterTest.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeFilterTest.java
index aefb4646c..87eed1921 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeFilterTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeFilterTest.java
@@ -3,7 +3,7 @@ package com.alibaba.fastjson2.autoType;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.filter.ContextAutoTypeBeforeHandler;
+import com.alibaba.fastjson2.filter.ContextAutoTypePreHandler;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashSet;
@@ -108,7 +108,7 @@ public class AutoTypeFilterTest {
                 (Object[]) JSONB.parseObject(
                         jsonbBytes,
                         Object.class,
-                        new ContextAutoTypeBeforeHandler(true),
+                        new ContextAutoTypePreHandler(true),
                         features
                 )
         );
diff --git a/core/src/test/java/com/alibaba/fastjson2/dubbo/DubboTest6.java b/core/src/test/java/com/alibaba/fastjson2/dubbo/DubboTest6.java
index 3e3871644..31c354036 100644
--- a/core/src/test/java/com/alibaba/fastjson2/dubbo/DubboTest6.java
+++ b/core/src/test/java/com/alibaba/fastjson2/dubbo/DubboTest6.java
@@ -4,7 +4,7 @@ import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.filter.ContextAutoTypeBeforeHandler;
+import com.alibaba.fastjson2.filter.ContextAutoTypePreHandler;
 import com.alibaba.fastjson2.writer.ObjectWriter;
 import org.apache.dubbo.springboot.demo.BusinessException;
 import org.apache.dubbo.springboot.demo.ParamsDTO;
@@ -23,7 +23,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class DubboTest6 {
     @Test
     public void test() {
-        ContextAutoTypeBeforeHandler contextAutoTypeBeforeHandler = new ContextAutoTypeBeforeHandler(true, ServiceException.class.getName(), BusinessException.class.getName());
+        ContextAutoTypePreHandler contextAutoTypeBeforeHandler = new ContextAutoTypePreHandler(true, ServiceException.class.getName(), BusinessException.class.getName());
         byte[] jsonbBytes = Base64.getDecoder().decode(base64);
         System.out.println(JSONB.toJSONString(jsonbBytes));
         ServiceException exception = (ServiceException) JSONB.parseObject(jsonbBytes, Object.class, contextAutoTypeBeforeHandler, readerFeatures);
@@ -50,7 +50,7 @@ public class DubboTest6 {
         assertSame(objectWriter, objectWriter1);
 
         byte[] jsonbBytes = JSONB.toBytes(proxy, writerFeatures);
-        ContextAutoTypeBeforeHandler contextAutoTypeBeforeHandler = new ContextAutoTypeBeforeHandler(true, ParamsDTO.class.getName());
+        ContextAutoTypePreHandler contextAutoTypeBeforeHandler = new ContextAutoTypePreHandler(true, ParamsDTO.class.getName());
 
         ParamsDTO paramsDTO1 = (ParamsDTO) JSONB.parseObject(jsonbBytes, Object.class, contextAutoTypeBeforeHandler, readerFeatures);
         assertEquals(paramsDTO.getParamsItems().size(), paramsDTO1.getParamsItems().size());
diff --git a/core/src/test/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandlerTest.java b/core/src/test/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandlerTest.java
index 99e8eb151..c3638c31a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandlerTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandlerTest.java
@@ -8,7 +8,7 @@ import static org.junit.jupiter.api.Assertions.assertNull;
 public class ContextAutoTypeBeforeHandlerTest {
     @Test
     public void checkAutoType() {
-        ContextAutoTypeBeforeHandler filter = new ContextAutoTypeBeforeHandler(new String[]{
+        ContextAutoTypePreHandler filter = new ContextAutoTypePreHandler(new String[]{
                 "",
                 ContextAutoTypeBeforeHandlerTest.class.getName() + ".",
                 null
@@ -23,7 +23,7 @@ public class ContextAutoTypeBeforeHandlerTest {
 
     @Test
     public void test0() {
-        ContextAutoTypeBeforeHandler filter = new ContextAutoTypeBeforeHandler(
+        ContextAutoTypePreHandler filter = new ContextAutoTypePreHandler(
                 new String[]{
                         "int",
                         "java.lang.String"
diff --git a/core/src/test/java/com/alibaba/fastjson2/issues/Issue749.java b/core/src/test/java/com/alibaba/fastjson2/issues/Issue749.java
index 6efc14e1f..0b792a198 100644
--- a/core/src/test/java/com/alibaba/fastjson2/issues/Issue749.java
+++ b/core/src/test/java/com/alibaba/fastjson2/issues/Issue749.java
@@ -3,7 +3,7 @@ package com.alibaba.fastjson2.issues;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.filter.ContextAutoTypeBeforeHandler;
+import com.alibaba.fastjson2.filter.ContextAutoTypePreHandler;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.*;
@@ -30,7 +30,7 @@ public class Issue749 {
         Object o = JSONB.parseObject(
                 bytes,
                 Object.class,
-                new ContextAutoTypeBeforeHandler(String.class)
+                new ContextAutoTypePreHandler(String.class)
         );
         System.out.println(o);
         System.out.println(o instanceof String[]);
@@ -39,7 +39,7 @@ public class Issue749 {
 
     @Test
     public void test2() {
-        ContextAutoTypeBeforeHandler filter = new ContextAutoTypeBeforeHandler(String.class);
+        ContextAutoTypePreHandler filter = new ContextAutoTypePreHandler(String.class);
 
         String s = "a.a.a.a";
         String[][] split = new String[][]{s.split("\\.")};
@@ -87,7 +87,7 @@ public class Issue749 {
 
     @Test
     public void test4() {
-        ContextAutoTypeBeforeHandler filter = new ContextAutoTypeBeforeHandler(String.class.getTypeName());
+        ContextAutoTypePreHandler filter = new ContextAutoTypePreHandler(String.class.getTypeName());
 
         String s = "a.a.a.a";
         String[][] split = new String[][]{s.split("\\.")};
diff --git a/extension-spring5/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/GenericFastJsonRedisSerializer.java b/extension-spring5/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/GenericFastJsonRedisSerializer.java
index cf9dce9ef..864f75f29 100644
--- a/extension-spring5/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/GenericFastJsonRedisSerializer.java
+++ b/extension-spring5/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/GenericFastJsonRedisSerializer.java
@@ -4,7 +4,7 @@ import com.alibaba.fastjson2.JSON;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.filter.ContextAutoTypeBeforeHandler;
+import com.alibaba.fastjson2.filter.ContextAutoTypePreHandler;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import org.springframework.data.redis.serializer.RedisSerializer;
 import org.springframework.data.redis.serializer.SerializationException;
@@ -28,7 +28,7 @@ public class GenericFastJsonRedisSerializer
 
     public GenericFastJsonRedisSerializer(String[] acceptNames, boolean jsonb) {
         this();
-        config.setReaderFilters(new ContextAutoTypeBeforeHandler(acceptNames));
+        config.setReaderFilters(new ContextAutoTypePreHandler(acceptNames));
         config.setJSONB(jsonb);
     }
 
diff --git a/extension-spring6/src/main/java/com/alibaba/fastjson2/support/spring6/data/redis/GenericFastJsonRedisSerializer.java b/extension-spring6/src/main/java/com/alibaba/fastjson2/support/spring6/data/redis/GenericFastJsonRedisSerializer.java
index 00e15475d..4f35ffedd 100644
--- a/extension-spring6/src/main/java/com/alibaba/fastjson2/support/spring6/data/redis/GenericFastJsonRedisSerializer.java
+++ b/extension-spring6/src/main/java/com/alibaba/fastjson2/support/spring6/data/redis/GenericFastJsonRedisSerializer.java
@@ -4,7 +4,7 @@ import com.alibaba.fastjson2.JSON;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.filter.ContextAutoTypeBeforeHandler;
+import com.alibaba.fastjson2.filter.ContextAutoTypePreHandler;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import org.springframework.data.redis.serializer.RedisSerializer;
 import org.springframework.data.redis.serializer.SerializationException;
@@ -28,7 +28,7 @@ public class GenericFastJsonRedisSerializer
 
     public GenericFastJsonRedisSerializer(String[] acceptNames, boolean jsonb) {
         this();
-        config.setReaderFilters(new ContextAutoTypeBeforeHandler(acceptNames));
+        config.setReaderFilters(new ContextAutoTypePreHandler(acceptNames));
         config.setJSONB(jsonb);
     }
 
diff --git a/extension/src/test/java/com/alibaba/fastjson2/config/FastJsonConfigTest.java b/extension/src/test/java/com/alibaba/fastjson2/config/FastJsonConfigTest.java
index 9b7132a42..e29705e0e 100644
--- a/extension/src/test/java/com/alibaba/fastjson2/config/FastJsonConfigTest.java
+++ b/extension/src/test/java/com/alibaba/fastjson2/config/FastJsonConfigTest.java
@@ -2,7 +2,7 @@ package com.alibaba.fastjson2.config;
 
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.filter.ContextAutoTypeBeforeHandler;
+import com.alibaba.fastjson2.filter.ContextAutoTypePreHandler;
 import com.alibaba.fastjson2.filter.SimplePropertyPreFilter;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import org.junit.jupiter.api.Test;
@@ -28,7 +28,7 @@ public class FastJsonConfigTest {
         assertEquals(fastJsonConfig.getReaderFeatures()[0], JSONReader.Feature.FieldBased);
         fastJsonConfig.setWriterFeatures(JSONWriter.Feature.FieldBased);
         assertEquals(fastJsonConfig.getWriterFeatures()[0], JSONWriter.Feature.FieldBased);
-        fastJsonConfig.setReaderFilters(new ContextAutoTypeBeforeHandler(new String[]{
+        fastJsonConfig.setReaderFilters(new ContextAutoTypePreHandler(new String[]{
                 "org.springframework.security.core.context.SecurityContextImpl"
         }));
         assertEquals(fastJsonConfig.getReaderFilters().length > 0, true);
diff --git a/fastjson1-compatible/src/main/java/com/alibaba/fastjson/serializer/ContextAutoTypeBeforeHandler.java b/fastjson1-compatible/src/main/java/com/alibaba/fastjson/serializer/ContextAutoTypeBeforeHandler.java
index 31ccac57e..ba47c135f 100644
--- a/fastjson1-compatible/src/main/java/com/alibaba/fastjson/serializer/ContextAutoTypeBeforeHandler.java
+++ b/fastjson1-compatible/src/main/java/com/alibaba/fastjson/serializer/ContextAutoTypeBeforeHandler.java
@@ -1,9 +1,11 @@
 package com.alibaba.fastjson.serializer;
 
+import com.alibaba.fastjson2.filter.ContextAutoTypePreHandler;
+
 public class ContextAutoTypeBeforeHandler
-        extends com.alibaba.fastjson2.filter.ContextAutoTypeBeforeHandler
+        extends ContextAutoTypePreHandler
         implements SerializeFilter {
     public ContextAutoTypeBeforeHandler(String[] acceptNames) {
-        super(acceptNames);
+        this.ContextAutoTypePreHandler(acceptNames);
     }
 }
 

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./mvnw -V --no-transfer-progress -Pgen-javadoc -Pgen-dokka clean package -Dsurefire.useFile=false -Dmaven.test.skip=false -DfailIfNoTests=false || true

