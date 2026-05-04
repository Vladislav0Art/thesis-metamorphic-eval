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
diff --git a/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandler.java b/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandler.java
index e3d0d3a4e..0787e2f06 100644
--- a/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandler.java
+++ b/core/src/main/java/com/alibaba/fastjson2/filter/ContextAutoTypeBeforeHandler.java
@@ -140,25 +140,19 @@ public class ContextAutoTypeBeforeHandler
     final ConcurrentMap<Integer, ConcurrentHashMap<Long, Class>> tclHashCaches = new ConcurrentHashMap<>();
     final Map<Long, Class> classCache = new ConcurrentHashMap<>(16, 0.75f, 1);
 
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
+    private Class putCacheIfAbsent(long typeNameHash, Class type) {
+        ClassLoader tcl = Thread.currentThread().getContextClassLoader();
+        if (tcl != null && tcl != JSON.class.getClassLoader()) {
+            int tclHash = System.identityHashCode(tcl);
+            ConcurrentHashMap<Long, Class> tclHashCache = tclHashCaches.get(tclHash);
+            if (tclHashCache == null) {
+                tclHashCaches.putIfAbsent(tclHash, new ConcurrentHashMap<>());
+                tclHashCache = tclHashCaches.get(tclHash);
+            }
 
-    public ContextAutoTypeBeforeHandler(boolean includeBasic) {
-        this(includeBasic, new String[0]);
+            return tclHashCache.putIfAbsent(typeNameHash, type);
+        }
+        return classCache.putIfAbsent(typeNameHash, type);
     }
 
     static String[] names(Collection<Class> types) {
@@ -174,51 +168,6 @@ public class ContextAutoTypeBeforeHandler
         return nameSet.toArray(new String[nameSet.size()]);
     }
 
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
     public Class<?> apply(long typeNameHash, Class<?> expectClass, long features) {
         ClassLoader tcl = Thread.currentThread().getContextClassLoader();
         if (tcl != null && tcl != JSON.class.getClassLoader()) {
@@ -312,18 +261,69 @@ public class ContextAutoTypeBeforeHandler
         return null;
     }
 
-    private Class putCacheIfAbsent(long typeNameHash, Class type) {
-        ClassLoader tcl = Thread.currentThread().getContextClassLoader();
-        if (tcl != null && tcl != JSON.class.getClassLoader()) {
-            int tclHash = System.identityHashCode(tcl);
-            ConcurrentHashMap<Long, Class> tclHashCache = tclHashCaches.get(tclHash);
-            if (tclHashCache == null) {
-                tclHashCaches.putIfAbsent(tclHash, new ConcurrentHashMap<>());
-                tclHashCache = tclHashCaches.get(tclHash);
+    public ContextAutoTypeBeforeHandler(Class... types) {
+        this(false, types);
+    }
+
+    public ContextAutoTypeBeforeHandler(boolean includeBasic, Class... types) {
+        this(
+                includeBasic,
+                names(
+                        Arrays.asList(types)
+                )
+        );
+    }
+
+    public ContextAutoTypeBeforeHandler(String... acceptNames) {
+        this(false, acceptNames);
+    }
+
+    public ContextAutoTypeBeforeHandler(boolean includeBasic) {
+        this(includeBasic, new String[0]);
+    }
+
+    public ContextAutoTypeBeforeHandler(boolean includeBasic, String... acceptNames) {
+        Set<String> nameSet = new HashSet<>();
+        if (includeBasic) {
+            for (Class basicType : BASIC_TYPES) {
+                String name = TypeUtils.getTypeName(basicType);
+                nameSet.add(name);
             }
+        }
 
-            return tclHashCache.putIfAbsent(typeNameHash, type);
+        for (String name : acceptNames) {
+            if (name == null || name.isEmpty()) {
+                continue;
+            }
+
+            Class mapping = TypeUtils.getMapping(name);
+            if (mapping != null) {
+                name = TypeUtils.getTypeName(mapping);
+            }
+            nameSet.add(name);
         }
-        return classCache.putIfAbsent(typeNameHash, type);
+
+        long[] array = new long[nameSet.size()];
+
+        int index = 0;
+        for (String name : nameSet) {
+            long hashCode = MAGIC_HASH_CODE;
+            for (int j = 0; j < name.length(); ++j) {
+                char ch = name.charAt(j);
+                if (ch == '$') {
+                    ch = '.';
+                }
+                hashCode ^= ch;
+                hashCode *= MAGIC_PRIME;
+            }
+
+            array[index++] = hashCode;
+        }
+
+        if (index != array.length) {
+            array = Arrays.copyOf(array, index);
+        }
+        Arrays.sort(array);
+        this.acceptHashCodes = array;
     }
 }
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
index f4808b2b7..05e41ebed 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
@@ -40,6 +40,258 @@ public final class ObjectReaderImplList
     ObjectReader itemObjectReader;
     volatile boolean instanceError;
 
+    @Override
+    public Object readObject(JSONReader jsonReader, Type fieldType, Object fieldName, long features) {
+        JSONReader.Context context = jsonReader.getContext();
+        if (itemObjectReader == null) {
+            itemObjectReader = context
+                    .getObjectReader(itemType);
+        }
+
+        if (jsonReader.isJSONB()) {
+            return readJSONBObject(jsonReader, fieldType, fieldName, 0);
+        }
+
+        if (jsonReader.readIfNull()) {
+            return null;
+        }
+
+        Collection list;
+        if (jsonReader.nextIfSet()) {
+            list = new HashSet();
+        } else {
+            list = (Collection) createInstance(context.getFeatures() | features);
+        }
+        char ch = jsonReader.current();
+        if (ch == '"') {
+            String str = jsonReader.readString();
+            if (itemClass == String.class) {
+                jsonReader.nextIfMatch(',');
+                list.add(str);
+                return list;
+            }
+
+            if (str.isEmpty()) {
+                jsonReader.nextIfMatch(',');
+                return null;
+            }
+
+            Function typeConvert = context.getProvider().getTypeConvert(String.class, itemType);
+            if (typeConvert != null) {
+                Object converted = typeConvert.apply(str);
+                jsonReader.nextIfMatch(',');
+                list.add(converted);
+                return list;
+            }
+            throw new JSONException(jsonReader.info());
+        }
+
+        if (!jsonReader.nextIfMatch('[')) {
+            if ((itemClass != Object.class && itemObjectReader != null) || (itemClass == Object.class && jsonReader.isObject())) {
+                Object item = itemObjectReader.readObject(jsonReader, itemType, 0, 0);
+                list.add(item);
+                if (builder != null) {
+                    list = (Collection) builder.apply(list);
+                }
+                return list;
+            }
+
+            throw new JSONException(jsonReader.info());
+        }
+
+        ObjectReader itemObjectReader = this.itemObjectReader;
+        Type itemType = this.itemType;
+        if (fieldType != null && fieldType != listType && fieldType instanceof ParameterizedType) {
+            Type[] actualTypeArguments = ((ParameterizedType) fieldType).getActualTypeArguments();
+            if (actualTypeArguments.length == 1) {
+                itemType = actualTypeArguments[0];
+                if (itemType != this.itemType) {
+                    itemObjectReader = jsonReader.getObjectReader(itemType);
+                }
+            }
+        }
+
+        for (int i = 0; ; ++i) {
+            if (jsonReader.nextIfMatch(']')) {
+                break;
+            }
+
+            Object item;
+            if (itemType == String.class) {
+                item = jsonReader.readString();
+            } else if (itemObjectReader != null) {
+                if (jsonReader.isReference()) {
+                    String reference = jsonReader.readReference();
+                    if ("..".equals(reference)) {
+                        item = this;
+                    } else {
+                        jsonReader.addResolveTask(list, i, JSONPath.of(reference));
+                        continue;
+                    }
+                } else {
+                    item = itemObjectReader.readObject(jsonReader, itemType, i, 0);
+                }
+            } else {
+                throw new JSONException(jsonReader.info("TODO : " + itemType));
+            }
+
+            list.add(item);
+
+            if (jsonReader.nextIfMatch(',')) {
+                continue;
+            }
+        }
+
+        jsonReader.nextIfMatch(',');
+
+        if (builder != null) {
+            return builder.apply(list);
+        }
+
+        return list;
+    }
+
+    @Override
+    public Object readJSONBObject(JSONReader jsonReader, Type fieldType, Object fieldName, long features) {
+        ObjectReader objectReader = jsonReader.checkAutoType(this.listClass, 0, features);
+
+        Function builder = this.builder;
+        Class listType = this.instanceType;
+        if (objectReader != null) {
+            listType = objectReader.getObjectClass();
+
+            if (listType == CLASS_UNMODIFIABLE_COLLECTION) {
+                listType = ArrayList.class;
+                builder = (Function<Collection, Collection>) Collections::unmodifiableCollection;
+            } else if (listType == CLASS_UNMODIFIABLE_LIST) {
+                listType = ArrayList.class;
+                builder = (Function<List, List>) Collections::unmodifiableList;
+            } else if (listType == CLASS_UNMODIFIABLE_SET) {
+                listType = LinkedHashSet.class;
+                builder = (Function<Set, Set>) Collections::unmodifiableSet;
+            } else if (listType == CLASS_UNMODIFIABLE_SORTED_SET) {
+                listType = TreeSet.class;
+                builder = (Function<SortedSet, SortedSet>) Collections::unmodifiableSortedSet;
+            } else if (listType == CLASS_UNMODIFIABLE_NAVIGABLE_SET) {
+                listType = TreeSet.class;
+                builder = (Function<NavigableSet, NavigableSet>) Collections::unmodifiableNavigableSet;
+            } else if (listType == CLASS_SINGLETON) {
+                listType = ArrayList.class;
+                builder = (Function<Collection, Collection>) ((Collection list) -> Collections.singleton(list.iterator().next()));
+            } else if (listType == CLASS_SINGLETON_LIST) {
+                listType = ArrayList.class;
+                builder = (Function<List, List>) ((List list) -> Collections.singletonList(list.get(0)));
+            }
+        }
+
+        int entryCnt = jsonReader.startArray();
+
+        if (entryCnt > 0 && itemObjectReader == null) {
+            itemObjectReader = jsonReader
+                    .getContext()
+                    .getObjectReader(itemType);
+        }
+
+        if (listType == CLASS_ARRAYS_LIST) {
+            Object[] array = new Object[entryCnt];
+            List list = Arrays.asList(array);
+            for (int i = 0; i < entryCnt; ++i) {
+                Object item;
+
+                if (jsonReader.isReference()) {
+                    String reference = jsonReader.readReference();
+                    if ("..".equals(reference)) {
+                        item = list;
+                    } else {
+                        item = null;
+                        jsonReader.addResolveTask((List) list, i, JSONPath.of(reference));
+                    }
+                } else {
+                    item = itemObjectReader.readJSONBObject(jsonReader, itemType, i, features);
+                }
+
+                array[i] = item;
+            }
+            return list;
+        }
+
+        Collection list;
+        if (listType == ArrayList.class) {
+            list = entryCnt > 0 ? new ArrayList(entryCnt) : new ArrayList();
+        } else if (listType == JSONArray.class) {
+            list = entryCnt > 0 ? new JSONArray(entryCnt) : new JSONArray();
+        } else if (listType == HashSet.class) {
+            list = new HashSet();
+        } else if (listType == LinkedHashSet.class) {
+            list = new LinkedHashSet();
+        } else if (listType == TreeSet.class) {
+            list = new TreeSet();
+        } else if (listType == CLASS_EMPTY_SET) {
+            list = Collections.emptySet();
+        } else if (listType == CLASS_EMPTY_LIST) {
+            list = Collections.emptyList();
+        } else if (listType == CLASS_SINGLETON_LIST) {
+            list = new ArrayList();
+            builder = (Function<Collection, Collection>) ((Collection items) -> Collections.singletonList(items.iterator().next()));
+        } else if (listType == CLASS_UNMODIFIABLE_LIST) {
+            list = new ArrayList();
+            builder = (Function<List, List>) ((List items) -> Collections.unmodifiableList(items));
+        } else if (listType != null && listType != this.listType) {
+            try {
+                list = (Collection) listType.newInstance();
+            } catch (InstantiationException | IllegalAccessException e) {
+                throw new JSONException(jsonReader.info("create instance error " + listType), e);
+            }
+        } else {
+            list = (Collection) createInstance(jsonReader.getContext().getFeatures() | features);
+        }
+
+        ObjectReader itemObjectReader = this.itemObjectReader;
+        Type itemType = this.itemType;
+        if (fieldType != null && fieldType != listType && fieldType instanceof ParameterizedType) {
+            Type[] actualTypeArguments = ((ParameterizedType) fieldType).getActualTypeArguments();
+            if (actualTypeArguments.length == 1) {
+                itemType = actualTypeArguments[0];
+                if (itemType != this.itemType) {
+                    itemObjectReader = jsonReader.getObjectReader(itemType);
+                }
+            }
+        }
+
+        for (int i = 0; i < entryCnt; ++i) {
+            Object item;
+
+            if (jsonReader.isReference()) {
+                String reference = jsonReader.readReference();
+                if ("..".equals(reference)) {
+                    item = list;
+                } else {
+                    jsonReader.addResolveTask(list, i, JSONPath.of(reference));
+                    if (list instanceof List) {
+                        item = null;
+                    } else {
+                        continue;
+                    }
+                }
+            } else {
+                ObjectReader autoTypeReader = jsonReader.checkAutoType(itemClass, itemClassNameHash, features);
+                if (autoTypeReader != null) {
+                    item = autoTypeReader.readJSONBObject(jsonReader, itemType, i, features);
+                } else {
+                    item = itemObjectReader.readJSONBObject(jsonReader, itemType, i, features);
+                }
+            }
+
+            list.add(item);
+        }
+
+        if (builder != null) {
+            return builder.apply(list);
+        }
+
+        return list;
+    }
+
     public static ObjectReader of(Type type, Class listClass, long features) {
         if (listClass == type && "".equals(listClass.getSimpleName())) {
             type = listClass.getGenericSuperclass();
@@ -160,23 +412,16 @@ public final class ObjectReaderImplList
         return new ObjectReaderImplList(type, listClass, instanceClass, itemType, builder);
     }
 
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
     @Override
     public Class getObjectClass() {
         return listClass;
     }
 
+    @Override
+    public FieldReader getFieldReader(long hashCode) {
+        return null;
+    }
+
     @Override
     public Function getBuildFunction() {
         return builder;
@@ -294,260 +539,15 @@ public final class ObjectReaderImplList
         return new ArrayList();
     }
 
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
+    public ObjectReaderImplList(Type listType, Class listClass, Class instanceType, Type itemType, Function builder) {
+        this.listType = listType;
+        this.listClass = listClass;
+        this.instanceType = instanceType;
+        this.instanceTypeHash = Fnv.hashCode64(TypeUtils.getTypeName(instanceType));
+        this.itemType = itemType;
+        this.itemClass = TypeUtils.getClass(itemType);
+        this.builder = builder;
+        this.itemClassName = itemClass != null ? TypeUtils.getTypeName(itemClass) : null;
+        this.itemClassNameHash = itemClassName != null ? Fnv.hashCode64(itemClassName) : 0;
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./mvnw -V --no-transfer-progress -Pgen-javadoc -Pgen-dokka clean package -Dsurefire.useFile=false -Dmaven.test.skip=false -DfailIfNoTests=false || true

