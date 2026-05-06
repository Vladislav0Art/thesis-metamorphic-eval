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
git checkout 3f6275bcc3cd40a57f6d257cdeec322d1b9ae06d

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderList.java b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderList.java
index a45f5d059..6382b0f98 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderList.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderList.java
@@ -81,7 +81,7 @@ public class FieldReaderList<T, V>
         if (initReader != null) {
             builder = this.initReader.getBuildFunction();
         } else {
-            if (objectReader instanceof ObjectReaderImplList) {
+            if (objectReader instanceof ListObjectReaderImpl) {
                 builder = objectReader.getBuildFunction();
             }
         }
@@ -224,10 +224,10 @@ public class FieldReaderList<T, V>
 
             ObjectReader autoTypeObjectReader = jsonReader.getObjectReaderAutoType(typeHash, fieldClass, features);
 
-            if (autoTypeObjectReader instanceof ObjectReaderImplList) {
-                ObjectReaderImplList listReader = (ObjectReaderImplList) autoTypeObjectReader;
+            if (autoTypeObjectReader instanceof ListObjectReaderImpl) {
+                ListObjectReaderImpl listReader = (ListObjectReaderImpl) autoTypeObjectReader;
 
-                autoTypeObjectReader = new ObjectReaderImplList(fieldType, fieldClass, listReader.instanceType, itemType, listReader.builder);
+                autoTypeObjectReader = new ListObjectReaderImpl(fieldType, fieldClass, listReader.instanceRawType, itemType, listReader.instanceBuilder);
             }
 
             if (autoTypeObjectReader == null) {
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderObject.java b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderObject.java
index 069e12a63..d4521c447 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderObject.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderObject.java
@@ -64,7 +64,7 @@ public class FieldReaderObject<T>
         if (fieldClass != null && Map.class.isAssignableFrom(fieldClass)) {
             return reader = ObjectReaderImplMap.of(fieldType, fieldClass, features);
         } else if (fieldClass != null && Collection.class.isAssignableFrom(fieldClass)) {
-            return reader = ObjectReaderImplList.of(fieldType, fieldClass, features);
+            return reader = ListObjectReaderImpl.ofType(fieldType, fieldClass, features);
         }
 
         return reader = jsonReader.getObjectReader(fieldType);
@@ -83,7 +83,7 @@ public class FieldReaderObject<T>
         if (Map.class.isAssignableFrom(fieldClass)) {
             return reader = ObjectReaderImplMap.of(fieldType, fieldClass, features);
         } else if (Collection.class.isAssignableFrom(fieldClass)) {
-            return reader = ObjectReaderImplList.of(fieldType, fieldClass, features);
+            return reader = ListObjectReaderImpl.ofType(fieldType, fieldClass, features);
         }
 
         return reader = context.getObjectReader(fieldType);
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ListObjectReaderImpl.java b/core/src/main/java/com/alibaba/fastjson2/reader/ListObjectReaderImpl.java
new file mode 100644
index 000000000..c99445ee8
--- /dev/null
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ListObjectReaderImpl.java
@@ -0,0 +1,639 @@
+package com.alibaba.fastjson2.reader;
+
+import com.alibaba.fastjson2.*;
+import com.alibaba.fastjson2.util.BeanUtils;
+import com.alibaba.fastjson2.util.Fnv;
+import com.alibaba.fastjson2.util.GuavaSupport;
+import com.alibaba.fastjson2.util.TypeUtils;
+
+import java.lang.reflect.*;
+import java.util.*;
+import java.util.function.Function;
+
+import static com.alibaba.fastjson2.util.JDKUtils.JVM_VERSION;
+import static com.alibaba.fastjson2.util.TypeUtils.CLASS_JSON_OBJECT_1x;
+
+public final class ListObjectReaderImpl
+        implements ObjectReader {
+    static final Class EMPTY_SET_CLASS = Collections.emptySet().getClass();
+    static final Class EMPTY_LIST_CLASS = Collections.emptyList().getClass();
+    static final Class SINGLETON_CLASS = Collections.singleton(0).getClass();
+    static final Class SINGLETON_LIST_CLASS = Collections.singletonList(0).getClass();
+    static final Class ARRAYS_AS_LIST_CLASS = Arrays.asList(0).getClass();
+
+    static final Class UNMODIFIABLE_COLLECTION_CLASS = Collections.unmodifiableCollection(Collections.emptyList()).getClass();
+    static final Class UNMODIFIABLE_LIST_CLASS = Collections.unmodifiableList(Collections.emptyList()).getClass();
+    static final Class UNMODIFIABLE_SET_CLASS = Collections.unmodifiableSet(Collections.emptySet()).getClass();
+    static final Class UNMODIFIABLE_SORTED_SET_CLASS = Collections.unmodifiableSortedSet(Collections.emptySortedSet()).getClass();
+    static final Class UNMODIFIABLE_NAVIGABLE_SET_CLASS = Collections.unmodifiableNavigableSet(Collections.emptyNavigableSet()).getClass();
+
+    public static ListObjectReaderImpl INSTANCE = new ListObjectReaderImpl(ArrayList.class, ArrayList.class, ArrayList.class, Object.class, null);
+
+    final Type listElementType;
+    final Class listImplClass;
+    final Class instanceRawType;
+    final long instanceTypeHashCode;
+    final Type elementType;
+    final Class elementClass;
+    final String itemClassFullName;
+    final long itemClassNameHashCode;
+    final Function instanceBuilder;
+    Object singletonListInstance;
+    ObjectReader elementObjectReader;
+    volatile boolean instanceErrorFlag;
+    volatile Constructor instanceConstructor;
+
+    public static ObjectReader ofType(Type requestedType, Class listImplClass, long featureFlags) {
+        if (listImplClass == requestedType && "".equals(listImplClass.getSimpleName())) {
+            requestedType = listImplClass.getGenericSuperclass();
+            listImplClass = listImplClass.getSuperclass();
+        }
+
+        Type elementType = Object.class;
+        Type rawClassType;
+        if (requestedType instanceof ParameterizedType) {
+            ParameterizedType genericParamType = (ParameterizedType) requestedType;
+            rawClassType = genericParamType.getRawType();
+            Type[] actualTypeArgs = genericParamType.getActualTypeArguments();
+            if (actualTypeArgs.length == 1) {
+                elementType = actualTypeArgs[0];
+            }
+        } else {
+            rawClassType = requestedType;
+            if (listImplClass != null) {
+                Type parentType = listImplClass.getGenericSuperclass();
+                if (parentType instanceof ParameterizedType) {
+                    ParameterizedType genericParamType = (ParameterizedType) parentType;
+                    rawClassType = genericParamType.getRawType();
+                    Type[] actualTypeArgs = genericParamType.getActualTypeArguments();
+                    if (actualTypeArgs.length == 1) {
+                        elementType = actualTypeArgs[0];
+                    }
+                }
+            }
+        }
+
+        if (listImplClass == null) {
+            listImplClass = TypeUtils.getClass(rawClassType);
+        }
+
+        Function instanceBuilder = null;
+        Class concreteInstanceClass;
+
+        if (listImplClass == Iterable.class
+                || listImplClass == Collection.class
+                || listImplClass == List.class
+                || listImplClass == AbstractCollection.class
+                || listImplClass == AbstractList.class
+        ) {
+            concreteInstanceClass = ArrayList.class;
+        } else if (listImplClass == Queue.class
+                || listImplClass == Deque.class
+                || listImplClass == AbstractSequentialList.class) {
+            concreteInstanceClass = LinkedList.class;
+        } else if (listImplClass == Set.class || listImplClass == AbstractSet.class) {
+            concreteInstanceClass = HashSet.class;
+        } else if (listImplClass == EnumSet.class) {
+            concreteInstanceClass = HashSet.class;
+            instanceBuilder = (elem) -> EnumSet.copyOf((Collection) elem);
+        } else if (listImplClass == NavigableSet.class || listImplClass == SortedSet.class) {
+            concreteInstanceClass = TreeSet.class;
+        } else if (listImplClass == SINGLETON_CLASS) {
+            concreteInstanceClass = ArrayList.class;
+            instanceBuilder = (Object inputObj) -> Collections.singleton(((List) inputObj).get(0));
+        } else if (listImplClass == SINGLETON_LIST_CLASS) {
+            concreteInstanceClass = ArrayList.class;
+            instanceBuilder = (Object inputObj) -> Collections.singletonList(((List) inputObj).get(0));
+        } else if (listImplClass == ARRAYS_AS_LIST_CLASS) {
+            concreteInstanceClass = ArrayList.class;
+            instanceBuilder = (Object inputObj) -> Arrays.asList(((List) inputObj).toArray());
+        } else if (listImplClass == UNMODIFIABLE_COLLECTION_CLASS) {
+            concreteInstanceClass = ArrayList.class;
+            instanceBuilder = (Object inputObj) -> Collections.unmodifiableCollection((Collection) inputObj);
+        } else if (listImplClass == UNMODIFIABLE_LIST_CLASS) {
+            concreteInstanceClass = ArrayList.class;
+            instanceBuilder = (Object inputObj) -> Collections.unmodifiableList((List) inputObj);
+        } else if (listImplClass == UNMODIFIABLE_SET_CLASS) {
+            concreteInstanceClass = LinkedHashSet.class;
+            instanceBuilder = (Object inputObj) -> Collections.unmodifiableSet((Set) inputObj);
+        } else if (listImplClass == UNMODIFIABLE_SORTED_SET_CLASS) {
+            concreteInstanceClass = TreeSet.class;
+            instanceBuilder = (Object inputObj) -> Collections.unmodifiableSortedSet((SortedSet) inputObj);
+        } else if (listImplClass == UNMODIFIABLE_NAVIGABLE_SET_CLASS) {
+            concreteInstanceClass = TreeSet.class;
+            instanceBuilder = (Object inputObj) -> Collections.unmodifiableNavigableSet((NavigableSet) inputObj);
+        } else {
+            String resolvedTypeName = listImplClass.getTypeName();
+            switch (resolvedTypeName) {
+                case "com.google.common.collect.ImmutableList":
+                case "com.google.common.collect.SingletonImmutableList":
+                case "com.google.common.collect.RegularImmutableList":
+                case "com.google.common.collect.AbstractMapBasedMultimap$RandomAccessWrappedList":
+                    concreteInstanceClass = ArrayList.class;
+                    instanceBuilder = GuavaSupport.immutableListConverter();
+                    break;
+                case "com.google.common.collect.ImmutableSet":
+                case "com.google.common.collect.SingletonImmutableSet":
+                case "com.google.common.collect.RegularImmutableSet":
+                    concreteInstanceClass = ArrayList.class;
+                    instanceBuilder = GuavaSupport.immutableSetConverter();
+                    break;
+                case "com.google.common.collect.Lists$TransformingRandomAccessList":
+                    concreteInstanceClass = ArrayList.class;
+                    break;
+                case "com.google.common.collect.Lists.TransformingSequentialList":
+                    concreteInstanceClass = LinkedList.class;
+                    break;
+                case "java.util.Collections$SynchronizedRandomAccessList":
+                    concreteInstanceClass = ArrayList.class;
+                    instanceBuilder = (Function<List, List>) Collections::synchronizedList;
+                    break;
+                case "java.util.Collections$SynchronizedCollection":
+                    concreteInstanceClass = ArrayList.class;
+                    instanceBuilder = (Function<Collection, Collection>) Collections::synchronizedCollection;
+                    break;
+                case "java.util.Collections$SynchronizedSet":
+                    concreteInstanceClass = HashSet.class;
+                    instanceBuilder = (Function<Set, Set>) Collections::synchronizedSet;
+                    break;
+                case "java.util.Collections$SynchronizedSortedSet":
+                    concreteInstanceClass = TreeSet.class;
+                    instanceBuilder = (Function<SortedSet, SortedSet>) Collections::synchronizedSortedSet;
+                    break;
+                case "java.util.Collections$SynchronizedNavigableSet":
+                    concreteInstanceClass = TreeSet.class;
+                    instanceBuilder = (Function<NavigableSet, NavigableSet>) Collections::synchronizedNavigableSet;
+                    break;
+                default:
+                    concreteInstanceClass = listImplClass;
+            }
+        }
+
+        switch (requestedType.getTypeName()) {
+            case "kotlin.collections.EmptySet":
+            case "kotlin.collections.EmptyList": {
+                Object emptyInstance;
+                Class<?> resolvedClass = (Class<?>) requestedType;
+                try {
+                    Field targetField = resolvedClass.getField("INSTANCE");
+                    if (!targetField.isAccessible()) {
+                        targetField.setAccessible(true);
+                    }
+                    emptyInstance = targetField.get(null);
+                } catch (NoSuchFieldException | IllegalAccessException ex) {
+                    throw new IllegalStateException("Failed to get singleton of " + requestedType, ex);
+                }
+                return new ListObjectReaderImpl(resolvedClass, emptyInstance);
+            }
+            case "java.util.Collections$EmptySet": {
+                return new ListObjectReaderImpl((Class) requestedType, Collections.emptySet());
+            }
+            case "java.util.Collections$EmptyList": {
+                return new ListObjectReaderImpl((Class) requestedType, Collections.emptyList());
+            }
+        }
+
+        if (elementType == String.class && instanceBuilder == null) {
+            return new ObjectReaderImplListStr(listImplClass, concreteInstanceClass);
+        }
+
+        if (elementType == Long.class && instanceBuilder == null) {
+            return new ObjectReaderImplListInt64(listImplClass, concreteInstanceClass);
+        }
+
+        return new ListObjectReaderImpl(requestedType, listImplClass, concreteInstanceClass, elementType, instanceBuilder);
+    }
+
+    ListObjectReaderImpl(Class listImplClass, Object singletonListInstance) {
+        this(listImplClass, listImplClass, listImplClass, Object.class, null);
+        this.singletonListInstance = singletonListInstance;
+    }
+
+    public ListObjectReaderImpl(Type listElementType, Class listImplClass, Class instanceRawType, Type elementType, Function instanceBuilder) {
+        this.listElementType = listElementType;
+        this.listImplClass = listImplClass;
+        this.instanceRawType = instanceRawType;
+        this.instanceTypeHashCode = Fnv.hashCode64(TypeUtils.getTypeName(instanceRawType));
+        this.elementType = elementType;
+        this.elementClass = TypeUtils.getClass(elementType);
+        this.instanceBuilder = instanceBuilder;
+        this.itemClassFullName = elementClass != null ? TypeUtils.getTypeName(elementClass) : null;
+        this.itemClassNameHashCode = itemClassFullName != null ? Fnv.hashCode64(itemClassFullName) : 0;
+    }
+
+    @Override
+    public Class getObjectClass() {
+        return listImplClass;
+    }
+
+    @Override
+    public Function getBuildFunction() {
+        return instanceBuilder;
+    }
+
+    @Override
+    public Object createInstance(Collection resultCollection) {
+        int elementCount = resultCollection.size();
+
+        if (elementCount == 0 && (listImplClass == List.class)) {
+            Collection resultSequence = new ArrayList();
+            if (instanceBuilder != null) {
+                return instanceBuilder.apply(resultSequence);
+            }
+            return resultSequence;
+        }
+
+        ObjectReaderProvider readerProvider = JSONFactory.getDefaultObjectReaderProvider();
+
+        Collection resultSequence;
+        if (instanceRawType == ArrayList.class) {
+            resultSequence = new ArrayList(resultCollection.size());
+        } else {
+            resultSequence = (Collection) createInstance(0L);
+        }
+
+        for (Object element : resultCollection) {
+            if (element == null) {
+                resultSequence.add(null);
+                continue;
+            }
+
+            Object val = element;
+            Class<?> valueTypeClass = val.getClass();
+            if ((valueTypeClass == JSONObject.class || valueTypeClass == CLASS_JSON_OBJECT_1x) && this.elementClass != valueTypeClass) {
+                if (elementObjectReader == null) {
+                    elementObjectReader = readerProvider.getObjectReader(elementType);
+                }
+                val = elementObjectReader.createInstance((JSONObject) val, 0L);
+            } else if (valueTypeClass != elementType) {
+                Function conversionFunction = readerProvider.getTypeConvert(valueTypeClass, elementType);
+                if (conversionFunction != null) {
+                    val = conversionFunction.apply(val);
+                } else if (element instanceof Map) {
+                    Map resultMap = (Map) element;
+                    if (elementObjectReader == null) {
+                        elementObjectReader = readerProvider.getObjectReader(elementType);
+                    }
+                    val = elementObjectReader.createInstance(resultMap, 0L);
+                } else if (val instanceof Collection) {
+                    if (elementObjectReader == null) {
+                        elementObjectReader = readerProvider.getObjectReader(elementType);
+                    }
+                    val = elementObjectReader.createInstance((Collection) val);
+                } else if (elementClass.isInstance(val)) {
+                    // skip
+                } else if (Enum.class.isAssignableFrom(elementClass)) {
+                    if (elementObjectReader == null) {
+                        elementObjectReader = readerProvider.getObjectReader(elementType);
+                    }
+
+                    if (elementObjectReader instanceof ObjectReaderImplEnum) {
+                        val = ((ObjectReaderImplEnum) elementObjectReader).getEnum((String) val);
+                    } else {
+                        throw new JSONException("can not convert from " + valueTypeClass + " to " + elementType);
+                    }
+                } else {
+                    throw new JSONException("can not convert from " + valueTypeClass + " to " + elementType);
+                }
+            }
+            resultSequence.add(val);
+        }
+
+        if (instanceBuilder != null) {
+            return instanceBuilder.apply(resultSequence);
+        }
+
+        return resultSequence;
+    }
+
+    @Override
+    public Object createInstance(long featureFlags) {
+        if (instanceRawType == ArrayList.class) {
+            return JVM_VERSION == 8 ? new ArrayList(10) : new ArrayList();
+        }
+
+        if (instanceRawType == LinkedList.class) {
+            return new LinkedList();
+        }
+
+        if (instanceRawType == HashSet.class) {
+            return new HashSet();
+        }
+
+        if (instanceRawType == LinkedHashSet.class) {
+            return new LinkedHashSet();
+        }
+
+        if (instanceRawType == TreeSet.class) {
+            return new TreeSet();
+        }
+
+        if (singletonListInstance != null) {
+            return singletonListInstance;
+        }
+
+        if (instanceRawType != null) {
+            JSONException parseError = null;
+            if (instanceConstructor == null && !BeanUtils.hasPublicDefaultConstructor(instanceRawType)) {
+                instanceConstructor = BeanUtils.getDefaultConstructor(instanceRawType, false);
+                instanceConstructor.setAccessible(true);
+            }
+            if (!instanceErrorFlag) {
+                try {
+                    if (instanceConstructor != null) {
+                        return instanceConstructor.newInstance();
+                    } else {
+                        return instanceRawType.newInstance();
+                    }
+                } catch (InstantiationException | IllegalAccessException | InvocationTargetException | RuntimeException ex) {
+                    instanceErrorFlag = true;
+                    parseError = new JSONException("create list error, type " + instanceRawType);
+                }
+            }
+
+            if (instanceErrorFlag && List.class.isAssignableFrom(instanceRawType.getSuperclass())) {
+                try {
+                    return instanceRawType.getSuperclass().newInstance();
+                } catch (InstantiationException | IllegalAccessException ex) {
+                    instanceErrorFlag = true;
+                    parseError = new JSONException("create list error, type " + instanceRawType);
+                }
+            }
+
+            if (parseError != null) {
+                throw parseError;
+            }
+        }
+
+        return new ArrayList();
+    }
+
+    @Override
+    public Object readJSONBObject(JSONReader jsonParser, Type fieldResolvedType, Object propertyName, long featureFlags) {
+        if (jsonParser.nextIfNull()) {
+            return null;
+        }
+
+        ObjectReader readerImpl = jsonParser.checkAutoType(this.listImplClass, 0, featureFlags);
+        Function instanceBuilder = this.instanceBuilder;
+        Class listElementType = this.instanceRawType;
+        if (readerImpl != null) {
+            if (readerImpl instanceof ListObjectReaderImpl) {
+                listElementType = ((ListObjectReaderImpl) readerImpl).instanceRawType;
+                instanceBuilder = ((ListObjectReaderImpl) readerImpl).instanceBuilder;
+            } else {
+                listElementType = readerImpl.getObjectClass();
+            }
+
+            if (listElementType == UNMODIFIABLE_COLLECTION_CLASS) {
+                listElementType = ArrayList.class;
+                instanceBuilder = (Function<Collection, Collection>) Collections::unmodifiableCollection;
+            } else if (listElementType == UNMODIFIABLE_LIST_CLASS) {
+                listElementType = ArrayList.class;
+                instanceBuilder = (Function<List, List>) Collections::unmodifiableList;
+            } else if (listElementType == UNMODIFIABLE_SET_CLASS) {
+                listElementType = LinkedHashSet.class;
+                instanceBuilder = (Function<Set, Set>) Collections::unmodifiableSet;
+            } else if (listElementType == UNMODIFIABLE_SORTED_SET_CLASS) {
+                listElementType = TreeSet.class;
+                instanceBuilder = (Function<SortedSet, SortedSet>) Collections::unmodifiableSortedSet;
+            } else if (listElementType == UNMODIFIABLE_NAVIGABLE_SET_CLASS) {
+                listElementType = TreeSet.class;
+                instanceBuilder = (Function<NavigableSet, NavigableSet>) Collections::unmodifiableNavigableSet;
+            } else if (listElementType == SINGLETON_CLASS) {
+                listElementType = ArrayList.class;
+                instanceBuilder = (Function<Collection, Collection>) ((Collection resultSequence) -> Collections.singleton(resultSequence.iterator().next()));
+            } else if (listElementType == SINGLETON_LIST_CLASS) {
+                listElementType = ArrayList.class;
+                instanceBuilder = (Function<List, List>) ((List resultSequence) -> Collections.singletonList(resultSequence.get(0)));
+            } else {
+                switch (listElementType.getTypeName()) {
+                    case "kotlin.collections.EmptySet":
+                    case "kotlin.collections.EmptyList": {
+                        return readerImpl.readObject(jsonParser, fieldResolvedType, propertyName, featureFlags);
+                    }
+                    default:
+                        break;
+                }
+            }
+        }
+
+        int entryCount = jsonParser.startArray();
+
+        if (entryCount > 0 && this.elementObjectReader == null) {
+            this.elementObjectReader = jsonParser
+                    .getContext()
+                    .getObjectReader(this.elementType);
+        }
+
+        if (listElementType == ARRAYS_AS_LIST_CLASS) {
+            Object[] objectArray = new Object[entryCount];
+            List resultSequence = Arrays.asList(objectArray);
+            for (int idx = 0; idx < entryCount; ++idx) {
+                Object element;
+
+                if (jsonParser.isReference()) {
+                    String refId = jsonParser.readReference();
+                    if ("..".equals(refId)) {
+                        element = resultSequence;
+                    } else {
+                        element = null;
+                        jsonParser.addResolveTask(resultSequence, idx, JSONPath.of(refId));
+                    }
+                } else {
+                    element = this.elementObjectReader.readJSONBObject(jsonParser, this.elementType, idx, featureFlags);
+                }
+
+                objectArray[idx] = element;
+            }
+            return resultSequence;
+        }
+
+        Collection resultSequence;
+        if (listElementType == ArrayList.class) {
+            resultSequence = entryCount > 0 ? new ArrayList(entryCount) : new ArrayList();
+        } else if (listElementType == JSONArray.class) {
+            resultSequence = entryCount > 0 ? new JSONArray(entryCount) : new JSONArray();
+        } else if (listElementType == HashSet.class) {
+            resultSequence = new HashSet();
+        } else if (listElementType == LinkedHashSet.class) {
+            resultSequence = new LinkedHashSet();
+        } else if (listElementType == TreeSet.class) {
+            resultSequence = new TreeSet();
+        } else if (listElementType == EMPTY_SET_CLASS) {
+            resultSequence = Collections.emptySet();
+        } else if (listElementType == EMPTY_LIST_CLASS) {
+            resultSequence = Collections.emptyList();
+        } else if (listElementType == SINGLETON_LIST_CLASS) {
+            resultSequence = new ArrayList();
+            instanceBuilder = (Function<Collection, Collection>) ((Collection elements) -> Collections.singletonList(elements.iterator().next()));
+        } else if (listElementType == UNMODIFIABLE_LIST_CLASS) {
+            resultSequence = new ArrayList();
+            instanceBuilder = (Function<List, List>) (Collections::unmodifiableList);
+        } else if (listElementType != null && EnumSet.class.isAssignableFrom(listElementType)) {
+            // maybe listType is java.util.RegularEnumSet or java.util.JumboEnumSet
+            resultSequence = new HashSet();
+            instanceBuilder = (elem) -> EnumSet.copyOf((Collection) elem);
+        } else if (listElementType != null && listElementType != this.listElementType) {
+            try {
+                resultSequence = (Collection) listElementType.newInstance();
+            } catch (InstantiationException | IllegalAccessException ex) {
+                throw new JSONException(jsonParser.info("create instance error " + listElementType), ex);
+            }
+        } else {
+            resultSequence = (Collection) createInstance(jsonParser.getContext().getFeatures() | featureFlags);
+        }
+
+        ObjectReader elementObjectReader = this.elementObjectReader;
+        Type elementType = this.elementType;
+        if (fieldResolvedType instanceof ParameterizedType) {
+            Type[] actualTypeArgs = ((ParameterizedType) fieldResolvedType).getActualTypeArguments();
+            if (actualTypeArgs.length == 1) {
+                elementType = actualTypeArgs[0];
+                if (elementType != this.elementType) {
+                    elementObjectReader = jsonParser.getObjectReader(elementType);
+                }
+            }
+        }
+
+        for (int idx = 0; idx < entryCount; ++idx) {
+            Object element;
+
+            if (jsonParser.isReference()) {
+                String refId = jsonParser.readReference();
+                if ("..".equals(refId)) {
+                    element = resultSequence;
+                } else {
+                    jsonParser.addResolveTask(resultSequence, idx, JSONPath.of(refId));
+                    if (resultSequence instanceof List) {
+                        element = null;
+                    } else {
+                        continue;
+                    }
+                }
+            } else {
+                ObjectReader autoReader = jsonParser.checkAutoType(elementClass, itemClassNameHashCode, featureFlags);
+                if (autoReader != null) {
+                    element = autoReader.readJSONBObject(jsonParser, elementType, idx, featureFlags);
+                } else {
+                    element = elementObjectReader.readJSONBObject(jsonParser, elementType, idx, featureFlags);
+                }
+            }
+
+            resultSequence.add(element);
+        }
+
+        if (instanceBuilder != null) {
+            return instanceBuilder.apply(resultSequence);
+        }
+
+        return resultSequence;
+    }
+
+    @Override
+    public Object readObject(JSONReader jsonParser, Type fieldResolvedType, Object propertyName, long featureFlags) {
+        JSONReader.Context readerContext = jsonParser.getContext();
+        if (this.elementObjectReader == null) {
+            this.elementObjectReader = readerContext
+                    .getObjectReader(this.elementType);
+        }
+
+        if (jsonParser.jsonb) {
+            return readJSONBObject(jsonParser, fieldResolvedType, propertyName, 0);
+        }
+
+        if (jsonParser.readIfNull()) {
+            return null;
+        }
+
+        Collection resultSequence;
+        if (jsonParser.nextIfSet()) {
+            resultSequence = new HashSet();
+        } else {
+            resultSequence = (Collection) createInstance(readerContext.getFeatures() | featureFlags);
+        }
+        char currChar = jsonParser.current();
+        if (currChar == '"') {
+            String stringValue = jsonParser.readString();
+            if (elementClass == String.class) {
+                jsonParser.nextIfComma();
+                resultSequence.add(stringValue);
+                return resultSequence;
+            }
+
+            if (stringValue.isEmpty()) {
+                jsonParser.nextIfComma();
+                return null;
+            }
+
+            Function conversionFunction = readerContext.getProvider().getTypeConvert(String.class, this.elementType);
+            if (conversionFunction != null) {
+                Object convertedValue = conversionFunction.apply(stringValue);
+                jsonParser.nextIfComma();
+                resultSequence.add(convertedValue);
+                return resultSequence;
+            }
+            throw new JSONException(jsonParser.info());
+        } else if (currChar == '[') {
+            jsonParser.next();
+        } else {
+            if ((elementClass != Object.class && this.elementObjectReader != null) || (elementClass == Object.class && jsonParser.isObject())) {
+                Object element = this.elementObjectReader.readObject(jsonParser, this.elementType, 0, 0);
+                resultSequence.add(element);
+                if (instanceBuilder != null) {
+                    resultSequence = (Collection) instanceBuilder.apply(resultSequence);
+                }
+                return resultSequence;
+            }
+
+            throw new JSONException(jsonParser.info());
+        }
+
+        ObjectReader elementObjectReader = this.elementObjectReader;
+        Type elementType = this.elementType;
+        if ((fieldResolvedType != listElementType) && (fieldResolvedType instanceof ParameterizedType)) {
+            Type[] actualTypeArgs = ((ParameterizedType) fieldResolvedType).getActualTypeArguments();
+            if (actualTypeArgs.length == 1) {
+                elementType = actualTypeArgs[0];
+                if (elementType != this.elementType) {
+                    elementObjectReader = jsonParser.getObjectReader(elementType);
+                }
+            }
+        }
+
+        for (int idx = 0; ; ++idx) {
+            if (jsonParser.nextIfArrayEnd()) {
+                break;
+            }
+
+            Object element;
+            if (elementType == String.class) {
+                element = jsonParser.readString();
+            } else if (elementObjectReader != null) {
+                if (jsonParser.isReference()) {
+                    String refId = jsonParser.readReference();
+                    if ("..".equals(refId)) {
+                        element = this;
+                    } else {
+                        jsonParser.addResolveTask(resultSequence, idx, JSONPath.of(refId));
+                        continue;
+                    }
+                } else {
+                    element = elementObjectReader.readObject(jsonParser, elementType, idx, 0);
+                }
+            } else {
+                throw new JSONException(jsonParser.info("TODO : " + elementType));
+            }
+
+            resultSequence.add(element);
+        }
+
+        jsonParser.nextIfComma();
+
+        if (instanceBuilder != null) {
+            return instanceBuilder.apply(resultSequence);
+        }
+
+        return resultSequence;
+    }
+}
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderBaseModule.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderBaseModule.java
index 9a5f1b533..3eaa81a46 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderBaseModule.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderBaseModule.java
@@ -1816,7 +1816,7 @@ public class ObjectReaderBaseModule
                 || type == AbstractList.class
                 || type == ArrayList.class
         ) {
-            return ObjectReaderImplList.of(type, null, 0);
+            return ListObjectReaderImpl.ofType(type, null, 0);
             // return new ObjectReaderImplList(type, (Class) type, ArrayList.class, Object.class, null);
         }
 
@@ -1825,17 +1825,17 @@ public class ObjectReaderBaseModule
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
@@ -1847,27 +1847,27 @@ public class ObjectReaderBaseModule
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
+                || type == ListObjectReaderImpl.ARRAYS_AS_LIST_CLASS
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
@@ -1895,7 +1895,7 @@ public class ObjectReaderBaseModule
             }
 
             if (Collection.class.isAssignableFrom(objectClass)) {
-                return ObjectReaderImplList.of(objectClass, objectClass, 0);
+                return ListObjectReaderImpl.ofType(objectClass, objectClass, 0);
             }
 
             if (objectClass.isArray()) {
@@ -2001,7 +2001,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, ArrayList.class);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -2014,7 +2014,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, LinkedList.class);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -2024,7 +2024,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, HashSet.class);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -2034,7 +2034,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, TreeSet.class);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -2051,7 +2051,7 @@ public class ObjectReaderBaseModule
                     } else if (itemClass == Long.class) {
                         return new ObjectReaderImplListInt64((Class) rawType, (Class) rawType);
                     } else {
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                     }
                 }
 
@@ -2059,7 +2059,7 @@ public class ObjectReaderBaseModule
                     case "com.google.common.collect.ImmutableList":
                     case "com.google.common.collect.ImmutableSet":
                     case "com.google.common.collect.SingletonImmutableSet":
-                        return ObjectReaderImplList.of(type, null, 0);
+                        return ListObjectReaderImpl.ofType(type, null, 0);
                 }
 
                 if (rawType == Optional.class) {
@@ -2102,7 +2102,7 @@ public class ObjectReaderBaseModule
                 return JdbcSupport.createDateReader((Class) type, null, null);
             case "java.util.RegularEnumSet":
             case "java.util.JumboEnumSet":
-                return ObjectReaderImplList.of(type, TypeUtils.getClass(type), 0);
+                return ListObjectReaderImpl.ofType(type, TypeUtils.getClass(type), 0);
             case "org.joda.time.Chronology":
                 return JodaSupport.createChronologyReader((Class) type);
             case "org.joda.time.LocalDate":
@@ -2150,7 +2150,7 @@ public class ObjectReaderBaseModule
             case "com.google.common.collect.SingletonImmutableSet":
             case "com.google.common.collect.RegularImmutableSet":
             case "com.google.common.collect.AbstractMapBasedMultimap$RandomAccessWrappedList":
-                return ObjectReaderImplList.of(type, null, 0);
+                return ListObjectReaderImpl.ofType(type, null, 0);
             case "com.carrotsearch.hppc.ByteArrayList":
             case "com.carrotsearch.hppc.ShortArrayList":
             case "com.carrotsearch.hppc.IntArrayList":
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
deleted file mode 100644
index 2af2137f4..000000000
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
+++ /dev/null
@@ -1,639 +0,5 @@
-package com.alibaba.fastjson2.reader;
 
 import com.alibaba.fastjson2.*;
-import com.alibaba.fastjson2.util.BeanUtils;
-import com.alibaba.fastjson2.util.Fnv;
-import com.alibaba.fastjson2.util.GuavaSupport;
-import com.alibaba.fastjson2.util.TypeUtils;
 
 import java.lang.reflect.*;
 import java.util.*;
-import java.util.function.Function;
-
-import static com.alibaba.fastjson2.util.JDKUtils.JVM_VERSION;
-import static com.alibaba.fastjson2.util.TypeUtils.CLASS_JSON_OBJECT_1x;
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
-    Object listSingleton;
-    ObjectReader itemObjectReader;
-    volatile boolean instanceError;
-    volatile Constructor constructor;
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
-                case "com.google.common.collect.SingletonImmutableList":
-                case "com.google.common.collect.RegularImmutableList":
-                case "com.google.common.collect.AbstractMapBasedMultimap$RandomAccessWrappedList":
-                    instanceClass = ArrayList.class;
-                    builder = GuavaSupport.immutableListConverter();
-                    break;
-                case "com.google.common.collect.ImmutableSet":
-                case "com.google.common.collect.SingletonImmutableSet":
-                case "com.google.common.collect.RegularImmutableSet":
-                    instanceClass = ArrayList.class;
-                    builder = GuavaSupport.immutableSetConverter();
-                    break;
-                case "com.google.common.collect.Lists$TransformingRandomAccessList":
-                    instanceClass = ArrayList.class;
-                    break;
-                case "com.google.common.collect.Lists.TransformingSequentialList":
-                    instanceClass = LinkedList.class;
-                    break;
-                case "java.util.Collections$SynchronizedRandomAccessList":
-                    instanceClass = ArrayList.class;
-                    builder = (Function<List, List>) Collections::synchronizedList;
-                    break;
-                case "java.util.Collections$SynchronizedCollection":
-                    instanceClass = ArrayList.class;
-                    builder = (Function<Collection, Collection>) Collections::synchronizedCollection;
-                    break;
-                case "java.util.Collections$SynchronizedSet":
-                    instanceClass = HashSet.class;
-                    builder = (Function<Set, Set>) Collections::synchronizedSet;
-                    break;
-                case "java.util.Collections$SynchronizedSortedSet":
-                    instanceClass = TreeSet.class;
-                    builder = (Function<SortedSet, SortedSet>) Collections::synchronizedSortedSet;
-                    break;
-                case "java.util.Collections$SynchronizedNavigableSet":
-                    instanceClass = TreeSet.class;
-                    builder = (Function<NavigableSet, NavigableSet>) Collections::synchronizedNavigableSet;
-                    break;
-                default:
-                    instanceClass = listClass;
-            }
-        }
-
-        switch (type.getTypeName()) {
-            case "kotlin.collections.EmptySet":
-            case "kotlin.collections.EmptyList": {
-                Object empty;
-                Class<?> clazz = (Class<?>) type;
-                try {
-                    Field field = clazz.getField("INSTANCE");
-                    if (!field.isAccessible()) {
-                        field.setAccessible(true);
-                    }
-                    empty = field.get(null);
-                } catch (NoSuchFieldException | IllegalAccessException e) {
-                    throw new IllegalStateException("Failed to get singleton of " + type, e);
-                }
-                return new ObjectReaderImplList(clazz, empty);
-            }
-            case "java.util.Collections$EmptySet": {
-                return new ObjectReaderImplList((Class) type, Collections.emptySet());
-            }
-            case "java.util.Collections$EmptyList": {
-                return new ObjectReaderImplList((Class) type, Collections.emptyList());
-            }
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
-    ObjectReaderImplList(Class listClass, Object listSingleton) {
-        this(listClass, listClass, listClass, Object.class, null);
-        this.listSingleton = listSingleton;
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
-            Collection list = new ArrayList();
-            if (builder != null) {
-                return builder.apply(list);
-            }
-            return list;
-        }
-
-        ObjectReaderProvider provider = JSONFactory.getDefaultObjectReaderProvider();
-
-        Collection list;
-        if (instanceType == ArrayList.class) {
-            list = new ArrayList(collection.size());
-        } else {
-            list = (Collection) createInstance(0L);
-        }
-
-        for (Object item : collection) {
-            if (item == null) {
-                list.add(null);
-                continue;
-            }
-
-            Object value = item;
-            Class<?> valueClass = value.getClass();
-            if ((valueClass == JSONObject.class || valueClass == CLASS_JSON_OBJECT_1x) && this.itemClass != valueClass) {
-                if (itemObjectReader == null) {
-                    itemObjectReader = provider.getObjectReader(itemType);
-                }
-                value = itemObjectReader.createInstance((JSONObject) value, 0L);
-            } else if (valueClass != itemType) {
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
-                } else if (Enum.class.isAssignableFrom(itemClass)) {
-                    if (itemObjectReader == null) {
-                        itemObjectReader = provider.getObjectReader(itemType);
-                    }
-
-                    if (itemObjectReader instanceof ObjectReaderImplEnum) {
-                        value = ((ObjectReaderImplEnum) itemObjectReader).getEnum((String) value);
-                    } else {
-                        throw new JSONException("can not convert from " + valueClass + " to " + itemType);
-                    }
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
-        if (listSingleton != null) {
-            return listSingleton;
-        }
-
-        if (instanceType != null) {
-            JSONException error = null;
-            if (constructor == null && !BeanUtils.hasPublicDefaultConstructor(instanceType)) {
-                constructor = BeanUtils.getDefaultConstructor(instanceType, false);
-                constructor.setAccessible(true);
-            }
-            if (!instanceError) {
-                try {
-                    if (constructor != null) {
-                        return constructor.newInstance();
-                    } else {
-                        return instanceType.newInstance();
-                    }
-                } catch (InstantiationException | IllegalAccessException | InvocationTargetException | RuntimeException e) {
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
-    public Object readJSONBObject(JSONReader jsonReader, Type fieldType, Object fieldName, long features) {
-        if (jsonReader.nextIfNull()) {
-            return null;
-        }
-
-        ObjectReader objectReader = jsonReader.checkAutoType(this.listClass, 0, features);
-        Function builder = this.builder;
-        Class listType = this.instanceType;
-        if (objectReader != null) {
-            if (objectReader instanceof ObjectReaderImplList) {
-                listType = ((ObjectReaderImplList) objectReader).instanceType;
-                builder = ((ObjectReaderImplList) objectReader).builder;
-            } else {
-                listType = objectReader.getObjectClass();
-            }
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
-            } else {
-                switch (listType.getTypeName()) {
-                    case "kotlin.collections.EmptySet":
-                    case "kotlin.collections.EmptyList": {
-                        return objectReader.readObject(jsonReader, fieldType, fieldName, features);
-                    }
-                    default:
-                        break;
-                }
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
-                        jsonReader.addResolveTask(list, i, JSONPath.of(reference));
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
-            builder = (Function<List, List>) (Collections::unmodifiableList);
-        } else if (listType != null && EnumSet.class.isAssignableFrom(listType)) {
-            // maybe listType is java.util.RegularEnumSet or java.util.JumboEnumSet
-            list = new HashSet();
-            builder = (o) -> EnumSet.copyOf((Collection) o);
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
-        if (fieldType instanceof ParameterizedType) {
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
-        if (jsonReader.jsonb) {
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
-                jsonReader.nextIfComma();
-                list.add(str);
-                return list;
-            }
-
-            if (str.isEmpty()) {
-                jsonReader.nextIfComma();
-                return null;
-            }
-
-            Function typeConvert = context.getProvider().getTypeConvert(String.class, itemType);
-            if (typeConvert != null) {
-                Object converted = typeConvert.apply(str);
-                jsonReader.nextIfComma();
-                list.add(converted);
-                return list;
-            }
-            throw new JSONException(jsonReader.info());
-        } else if (ch == '[') {
-            jsonReader.next();
-        } else {
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
-        if ((fieldType != listType) && (fieldType instanceof ParameterizedType)) {
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
-            if (jsonReader.nextIfArrayEnd()) {
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
-        }
-
-        jsonReader.nextIfComma();
-
-        if (builder != null) {
-            return builder.apply(list);
-        }
-
-        return list;
-    }
-}
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplListStr.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplListStr.java
index 7ba854c2f..7e1a532ff 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplListStr.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplListStr.java
@@ -10,7 +10,8 @@ import java.lang.reflect.Type;
 import java.util.*;
 import java.util.function.Function;
 
 import static com.alibaba.fastjson2.reader.ObjectReaderImplList.*;
+import static com.alibaba.fastjson2.reader.ListObjectReaderImpl.*;
 
 public final class ObjectReaderImplListStr
         implements ObjectReader {
@@ -85,7 +86,7 @@ public final class ObjectReaderImplListStr
             instanceType = objectReader.getObjectClass();
         }
 
-        if (instanceType == CLASS_ARRAYS_LIST) {
+        if (instanceType == ARRAYS_AS_LIST_CLASS) {
             int entryCnt = jsonReader.startArray();
             String[] array = new String[entryCnt];
             for (int i = 0; i < entryCnt; ++i) {
@@ -102,25 +103,25 @@ public final class ObjectReaderImplListStr
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
index f999b905f..98ea926c6 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java
@@ -370,9 +370,9 @@ public class ObjectReaderProvider
             }
             Class keyClass = TypeUtils.getClass(mapTyped.keyType);
             return keyClass != null && keyClass.getClassLoader() == classLoader;
-        } else if (objectReader instanceof ObjectReaderImplList) {
-            ObjectReaderImplList list = (ObjectReaderImplList) objectReader;
-            return list.itemClass != null && list.itemClass.getClassLoader() == classLoader;
+        } else if (objectReader instanceof ListObjectReaderImpl) {
+            ListObjectReaderImpl list = (ListObjectReaderImpl) objectReader;
+            return list.elementClass != null && list.elementClass.getClassLoader() == classLoader;
         } else if (objectReader instanceof ObjectReaderImplOptional) {
             Class itemClass = ((ObjectReaderImplOptional) objectReader).itemClass;
             return itemClass != null && itemClass.getClassLoader() == classLoader;
@@ -805,7 +805,7 @@ public class ObjectReaderProvider
                     }
                 }
                 if (typeArguments.length == 1 && ArrayList.class.isAssignableFrom(rawClass)) {
-                    return ObjectReaderImplList.of(objectType, rawClass, 0);
+                    return ListObjectReaderImpl.ofType(objectType, rawClass, 0);
                 }
             }
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONTest.java b/core/src/test/java/com/alibaba/fastjson2/JSONTest.java
index 2439c7144..98ab5a826 100644
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
@@ -778,9 +778,9 @@ public class JSONTest {
 
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
@@ -803,9 +803,9 @@ public class JSONTest {
                         }.getType()))
                         .get(0));
 
-        new ObjectReaderImplList(MyList.class, MyList.class, MyList.class, Integer.class, null).createInstance();
+        new ListObjectReaderImpl(MyList.class, MyList.class, MyList.class, Integer.class, null).createInstance();
 
-        Object instance = new ObjectReaderImplList(MyList0.class, MyList0.class, MyList0.class, Integer.class, null).createInstance();
+        Object instance = new ListObjectReaderImpl(MyList0.class, MyList0.class, MyList0.class, Integer.class, null).createInstance();
         assertNotNull(instance);
     }
 
 

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./mvnw -V --no-transfer-progress -Pgen-javadoc -Pgen-dokka clean package -Dsurefire.useFile=false -Dmaven.test.skip=false -DfailIfNoTests=false || true

