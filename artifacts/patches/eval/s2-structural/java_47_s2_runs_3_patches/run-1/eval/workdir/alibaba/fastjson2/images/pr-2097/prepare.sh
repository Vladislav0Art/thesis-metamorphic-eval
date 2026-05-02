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
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
index 2af2137f4..cdaa446b7 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderImplList.java
@@ -43,6 +43,275 @@ public final class ObjectReaderImplList
     volatile boolean instanceError;
     volatile Constructor constructor;
 
+    @Override
+    public Object readObject(JSONReader jsonReader, Type fieldType, Object fieldName, long features) {
+        JSONReader.Context context = jsonReader.getContext();
+        if (itemObjectReader == null) {
+            itemObjectReader = context
+                    .getObjectReader(itemType);
+        }
+
+        if (jsonReader.jsonb) {
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
+                jsonReader.nextIfComma();
+                list.add(str);
+                return list;
+            }
+
+            if (str.isEmpty()) {
+                jsonReader.nextIfComma();
+                return null;
+            }
+
+            Function typeConvert = context.getProvider().getTypeConvert(String.class, itemType);
+            if (typeConvert != null) {
+                Object converted = typeConvert.apply(str);
+                jsonReader.nextIfComma();
+                list.add(converted);
+                return list;
+            }
+            throw new JSONException(jsonReader.info());
+        } else if (ch == '[') {
+            jsonReader.next();
+        } else {
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
+        if ((fieldType != listType) && (fieldType instanceof ParameterizedType)) {
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
+            if (jsonReader.nextIfArrayEnd()) {
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
+        }
+
+        jsonReader.nextIfComma();
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
+        if (jsonReader.nextIfNull()) {
+            return null;
+        }
+
+        ObjectReader objectReader = jsonReader.checkAutoType(this.listClass, 0, features);
+        Function builder = this.builder;
+        Class listType = this.instanceType;
+        if (objectReader != null) {
+            if (objectReader instanceof ObjectReaderImplList) {
+                listType = ((ObjectReaderImplList) objectReader).instanceType;
+                builder = ((ObjectReaderImplList) objectReader).builder;
+            } else {
+                listType = objectReader.getObjectClass();
+            }
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
+            } else {
+                switch (listType.getTypeName()) {
+                    case "kotlin.collections.EmptySet":
+                    case "kotlin.collections.EmptyList": {
+                        return objectReader.readObject(jsonReader, fieldType, fieldName, features);
+                    }
+                    default:
+                        break;
+                }
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
+                        jsonReader.addResolveTask(list, i, JSONPath.of(reference));
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
+            builder = (Function<List, List>) (Collections::unmodifiableList);
+        } else if (listType != null && EnumSet.class.isAssignableFrom(listType)) {
+            // maybe listType is java.util.RegularEnumSet or java.util.JumboEnumSet
+            list = new HashSet();
+            builder = (o) -> EnumSet.copyOf((Collection) o);
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
+        if (fieldType instanceof ParameterizedType) {
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
@@ -204,323 +473,82 @@ public final class ObjectReaderImplList
         return new ObjectReaderImplList(type, listClass, instanceClass, itemType, builder);
     }
 
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
+    @Override
+    public Class getObjectClass() {
+        return listClass;
+    }
 
-                array[i] = item;
+    @Override
+    public Function getBuildFunction() {
+        return builder;
+    }
+
+    @Override
+    public Object createInstance(Collection collection) {
+        int size = collection.size();
+
+        if (size == 0 && (listClass == List.class)) {
+            Collection list = new ArrayList();
+            if (builder != null) {
+                return builder.apply(list);
             }
             return list;
         }
 
+        ObjectReaderProvider provider = JSONFactory.getDefaultObjectReaderProvider();
+
         Collection list;
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
+        if (instanceType == ArrayList.class) {
+            list = new ArrayList(collection.size());
         } else {
-            list = (Collection) createInstance(jsonReader.getContext().getFeatures() | features);
+            list = (Collection) createInstance(0L);
         }
 
-        ObjectReader itemObjectReader = this.itemObjectReader;
-        Type itemType = this.itemType;
-        if (fieldType instanceof ParameterizedType) {
-            Type[] actualTypeArguments = ((ParameterizedType) fieldType).getActualTypeArguments();
-            if (actualTypeArguments.length == 1) {
-                itemType = actualTypeArguments[0];
-                if (itemType != this.itemType) {
-                    itemObjectReader = jsonReader.getObjectReader(itemType);
-                }
+        for (Object item : collection) {
+            if (item == null) {
+                list.add(null);
+                continue;
             }
-        }
 
-        for (int i = 0; i < entryCnt; ++i) {
-            Object item;
+            Object value = item;
+            Class<?> valueClass = value.getClass();
+            if ((valueClass == JSONObject.class || valueClass == CLASS_JSON_OBJECT_1x) && this.itemClass != valueClass) {
+                if (itemObjectReader == null) {
+                    itemObjectReader = provider.getObjectReader(itemType);
+                }
+                value = itemObjectReader.createInstance((JSONObject) value, 0L);
+            } else if (valueClass != itemType) {
+                Function typeConvert = provider.getTypeConvert(valueClass, itemType);
+                if (typeConvert != null) {
+                    value = typeConvert.apply(value);
+                } else if (item instanceof Map) {
+                    Map map = (Map) item;
+                    if (itemObjectReader == null) {
+                        itemObjectReader = provider.getObjectReader(itemType);
+                    }
+                    value = itemObjectReader.createInstance(map, 0L);
+                } else if (value instanceof Collection) {
+                    if (itemObjectReader == null) {
+                        itemObjectReader = provider.getObjectReader(itemType);
+                    }
+                    value = itemObjectReader.createInstance((Collection) value);
+                } else if (itemClass.isInstance(value)) {
+                    // skip
+                } else if (Enum.class.isAssignableFrom(itemClass)) {
+                    if (itemObjectReader == null) {
+                        itemObjectReader = provider.getObjectReader(itemType);
+                    }
 
-            if (jsonReader.isReference()) {
-                String reference = jsonReader.readReference();
-                if ("..".equals(reference)) {
-                    item = list;
-                } else {
-                    jsonReader.addResolveTask(list, i, JSONPath.of(reference));
-                    if (list instanceof List) {
-                        item = null;
+                    if (itemObjectReader instanceof ObjectReaderImplEnum) {
+                        value = ((ObjectReaderImplEnum) itemObjectReader).getEnum((String) value);
                     } else {
-                        continue;
+                        throw new JSONException("can not convert from " + valueClass + " to " + itemType);
                     }
-                }
-            } else {
-                ObjectReader autoTypeReader = jsonReader.checkAutoType(itemClass, itemClassNameHash, features);
-                if (autoTypeReader != null) {
-                    item = autoTypeReader.readJSONBObject(jsonReader, itemType, i, features);
                 } else {
-                    item = itemObjectReader.readJSONBObject(jsonReader, itemType, i, features);
+                    throw new JSONException("can not convert from " + valueClass + " to " + itemType);
                 }
             }
-
-            list.add(item);
+            list.add(value);
         }
 
         if (builder != null) {
@@ -531,109 +559,81 @@ public final class ObjectReaderImplList
     }
 
     @Override
-    public Object readObject(JSONReader jsonReader, Type fieldType, Object fieldName, long features) {
-        JSONReader.Context context = jsonReader.getContext();
-        if (itemObjectReader == null) {
-            itemObjectReader = context
-                    .getObjectReader(itemType);
+    public Object createInstance(long features) {
+        if (instanceType == ArrayList.class) {
+            return JVM_VERSION == 8 ? new ArrayList(10) : new ArrayList();
         }
 
-        if (jsonReader.jsonb) {
-            return readJSONBObject(jsonReader, fieldType, fieldName, 0);
+        if (instanceType == LinkedList.class) {
+            return new LinkedList();
         }
 
-        if (jsonReader.readIfNull()) {
-            return null;
+        if (instanceType == HashSet.class) {
+            return new HashSet();
         }
 
-        Collection list;
-        if (jsonReader.nextIfSet()) {
-            list = new HashSet();
-        } else {
-            list = (Collection) createInstance(context.getFeatures() | features);
+        if (instanceType == LinkedHashSet.class) {
+            return new LinkedHashSet();
         }
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
 
-            throw new JSONException(jsonReader.info());
+        if (instanceType == TreeSet.class) {
+            return new TreeSet();
         }
 
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
+        if (listSingleton != null) {
+            return listSingleton;
         }
 
-        for (int i = 0; ; ++i) {
-            if (jsonReader.nextIfArrayEnd()) {
-                break;
+        if (instanceType != null) {
+            JSONException error = null;
+            if (constructor == null && !BeanUtils.hasPublicDefaultConstructor(instanceType)) {
+                constructor = BeanUtils.getDefaultConstructor(instanceType, false);
+                constructor.setAccessible(true);
             }
-
-            Object item;
-            if (itemType == String.class) {
-                item = jsonReader.readString();
-            } else if (itemObjectReader != null) {
-                if (jsonReader.isReference()) {
-                    String reference = jsonReader.readReference();
-                    if ("..".equals(reference)) {
-                        item = this;
+            if (!instanceError) {
+                try {
+                    if (constructor != null) {
+                        return constructor.newInstance();
                     } else {
-                        jsonReader.addResolveTask(list, i, JSONPath.of(reference));
-                        continue;
+                        return instanceType.newInstance();
                     }
-                } else {
-                    item = itemObjectReader.readObject(jsonReader, itemType, i, 0);
+                } catch (InstantiationException | IllegalAccessException | InvocationTargetException | RuntimeException e) {
+                    instanceError = true;
+                    error = new JSONException("create list error, type " + instanceType);
                 }
-            } else {
-                throw new JSONException(jsonReader.info("TODO : " + itemType));
             }
 
-            list.add(item);
+            if (instanceError && List.class.isAssignableFrom(instanceType.getSuperclass())) {
+                try {
+                    return instanceType.getSuperclass().newInstance();
+                } catch (InstantiationException | IllegalAccessException e) {
+                    instanceError = true;
+                    error = new JSONException("create list error, type " + instanceType);
+                }
+            }
+
+            if (error != null) {
+                throw error;
+            }
         }
 
-        jsonReader.nextIfComma();
+        return new ArrayList();
+    }
 
-        if (builder != null) {
-            return builder.apply(list);
-        }
+    ObjectReaderImplList(Class listClass, Object listSingleton) {
+        this(listClass, listClass, listClass, Object.class, null);
+        this.listSingleton = listSingleton;
+    }
 
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

