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
git checkout 3aed80608b36c310d0fe5f240f49d670b3638698

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/core/src/main/java/com/alibaba/fastjson2/JSON.java b/core/src/main/java/com/alibaba/fastjson2/JSON.java
index b6a0ff2ce..005ba3558 100644
--- a/core/src/main/java/com/alibaba/fastjson2/JSON.java
+++ b/core/src/main/java/com/alibaba/fastjson2/JSON.java
@@ -21,35 +21,310 @@ public interface JSON {
     String VERSION = "2.0.2";
 
     /**
-     * Parse JSON {@link String} into {@link JSONArray} or {@link JSONObject}
+     * Serialize Java Object to JSON and write to {@link OutputStream} with specified {@link JSONReader.Feature}s enabled
      *
-     * @param text the JSON {@link String} to be parsed
-     * @return Object
+     * @param out      {@link OutputStream} to be written
+     * @param object   Java Object to be serialized into JSON
+     * @param features features to be enabled in serialization
+     * @throws JSONException if an I/O error occurs. In particular, a {@link JSONException} may be thrown if the output stream has been closed
      */
-    static Object parse(String text) {
-        if (text == null) {
+    static int writeTo(OutputStream out, Object object, JSONWriter.Feature... features) {
+        try (JSONWriter writer = JSONWriter.ofUTF8(features)) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                writer.setRootObject(object);
+
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+
+            return writer.flushTo(out);
+        } catch (IOException e) {
+            throw new JSONException(e.getMessage(), e);
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON and write to {@link OutputStream} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param out      {@link OutputStream} to be written
+     * @param object   Java Object to be serialized into JSON
+     * @param filters  specifies the filter to use in serialization
+     * @param features features to be enabled in serialization
+     * @throws JSONException if an I/O error occurs. In particular, a {@link JSONException} may be thrown if the output stream has been closed
+     */
+    static int writeTo(OutputStream out, Object object, Filter[] filters, JSONWriter.Feature... features) {
+        try (JSONWriter writer = JSONWriter.ofUTF8(features)) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                writer.setRootObject(object);
+                if (filters != null && filters.length != 0) {
+                    writer.context.configFilter(filters);
+                }
+
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+
+            return writer.flushTo(out);
+        } catch (IOException e) {
+            throw new JSONException(e.getMessage(), e);
+        }
+    }
+
+    /**
+     * Convert the Object to the target type
+     *
+     * @param object Java Object to be converted
+     * @param clazz  converted goal class
+     */
+    static <T> T toJavaObject(Object object, Class<T> clazz) {
+        if (object == null) {
             return null;
         }
-        JSONReader reader = JSONReader.of(text);
-        ObjectReader<?> objectReader = reader.getObjectReader(Object.class);
-        return objectReader.readObject(reader, 0);
+        if (object instanceof JSONObject) {
+            return ((JSONObject) object).toJavaObject(clazz);
+        }
+
+        return TypeUtils.cast(object, clazz);
     }
 
     /**
-     * Parse JSON {@link String} into {@link JSONArray} or {@link JSONObject} with specified {@link JSONReader.Feature}s enabled
+     * Serialize Java Object to JSON {@link String}
      *
-     * @param text     the JSON {@link String} to be parsed
-     * @param features features to be enabled in parsing
-     * @return Object
+     * @param object Java Object to be serialized into JSON {@link String}
      */
-    static Object parse(String text, JSONReader.Feature... features) {
-        if (text == null) {
+    static String toJSONString(Object object) {
+        try (JSONWriter writer = JSONWriter.of()) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.toString();
+        } catch (NullPointerException | NumberFormatException ex) {
+            throw new JSONException("toJSONString error", ex);
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param object   Java Object to be serialized into JSON {@link String}
+     * @param features features to be enabled in serialization
+     */
+    static String toJSONString(Object object, JSONWriter.Feature... features) {
+        JSONWriter.Context writeContext = new JSONWriter.Context(JSONFactory.defaultObjectWriterProvider, features);
+
+        boolean pretty = (writeContext.features & JSONWriter.Feature.PrettyFormat.mask) != 0;
+        JSONWriterUTF16 jsonWriter = JDKUtils.JVM_VERSION == 8 ? new JSONWriterUTF16JDK8(writeContext) : new JSONWriterUTF16(writeContext);
+
+        try (JSONWriter writer = pretty ?
+                new JSONWriterPretty(jsonWriter) : jsonWriter) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                writer.setRootObject(object);
+                Class<?> valueClass = object.getClass();
+
+                boolean fieldBased = (writeContext.features & JSONWriter.Feature.FieldBased.mask) != 0;
+                ObjectWriter<?> objectWriter = writeContext.provider.getObjectWriter(valueClass, valueClass, fieldBased);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.toString();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param object   Java Object to be serialized into JSON {@link String}
+     * @param filters  specifies the filter to use in serialization
+     * @param features features to be enabled in serialization
+     */
+    static String toJSONString(Object object, Filter[] filters, JSONWriter.Feature... features) {
+        try (JSONWriter writer = JSONWriter.of(features)) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                writer.setRootObject(object);
+                if (filters != null && filters.length != 0) {
+                    writer.context.configFilter(filters);
+                }
+
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.toString();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param object   Java Object to be serialized into JSON {@link String}
+     * @param filter   specify a filter to use in serialization
+     * @param features features to be enabled in serialization
+     */
+    static String toJSONString(Object object, Filter filter, JSONWriter.Feature... features) {
+        try (JSONWriter writer = JSONWriter.of(features)) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                writer.setRootObject(object);
+                if (filter != null) {
+                    writer.context.configFilter(filter);
+                }
+
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.toString();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param object   Java Object to be serialized into JSON {@link String}
+     * @param format   the specified date format
+     * @param features features to be enabled in serialization
+     */
+    static String toJSONString(Object object, String format, JSONWriter.Feature... features) {
+        try (JSONWriter writer = JSONWriter.of(features)) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                writer.setRootObject(object);
+                writer.context.setDateFormat(format);
+
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.toString();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON byte array
+     *
+     * @param object Java Object to be serialized into JSON byte array
+     */
+    static byte[] toJSONBytes(Object object) {
+        try (JSONWriter writer = JSONWriter.ofUTF8()) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.getBytes();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON byte array
+     *
+     * @param object  Java Object to be serialized into JSON byte array
+     * @param filters specifies the filter to use in serialization
+     */
+    static byte[] toJSONBytes(Object object, Filter... filters) {
+        try (JSONWriter writer = JSONWriter.ofUTF8()) {
+            if (filters != null && filters.length != 0) {
+                writer.context.configFilter(filters);
+            }
+
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.getBytes();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON byte array with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param object   Java Object to be serialized into JSON byte array
+     * @param features features to be enabled in serialization
+     */
+    static byte[] toJSONBytes(Object object, JSONWriter.Feature... features) {
+        try (JSONWriter writer = JSONWriter.ofUTF8(features)) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                writer.setRootObject(object);
+
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.getBytes();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON byte array with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param object   Java Object to be serialized into JSON byte array
+     * @param filters  specifies the filter to use in serialization
+     * @param features features to be enabled in serialization
+     */
+    static byte[] toJSONBytes(Object object, Filter[] filters, JSONWriter.Feature... features) {
+        try (JSONWriter writer = JSONWriter.ofUTF8(features)) {
+            if (object == null) {
+                writer.writeNull();
+            } else {
+                writer.setRootObject(object);
+                if (filters != null && filters.length != 0) {
+                    writer.context.configFilter(filters);
+                }
+
+                Class<?> valueClass = object.getClass();
+                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
+                objectWriter.write(writer, object, null, null, 0);
+            }
+            return writer.getBytes();
+        }
+    }
+
+    /**
+     * Convert Java object order to {@link JSONArray} or {@link JSONObject}
+     *
+     * @param object Java Object to be converted
+     * @return Java Object
+     */
+    static Object toJSON(Object object) {
+        if (object == null) {
             return null;
         }
-        JSONReader reader = JSONReader.of(text);
-        reader.context.config(features);
-        ObjectReader<?> objectReader = reader.getObjectReader(Object.class);
-        return objectReader.readObject(reader, 0);
+        if (object instanceof JSONObject || object instanceof JSONArray) {
+            return object;
+        }
+
+        String str = JSON.toJSONString(object);
+        return JSON.parse(str);
+    }
+
+    static boolean register(Type type, ObjectReader objectReader) {
+        return JSONFactory.getDefaultObjectReaderProvider().register(type, objectReader);
+    }
+
+    static boolean register(Type type, ObjectWriter objectReader) {
+        return JSONFactory.defaultObjectWriterProvider.register(type, objectReader);
     }
 
     /**
@@ -262,345 +537,121 @@ public interface JSON {
      * @throws IndexOutOfBoundsException If the offset and the length arguments index characters outside the bounds of the bytes array
      */
     @SuppressWarnings("unchecked")
-    static <T> T parseObject(byte[] bytes, int offset, int length, Charset charset, Type type) {
-        if (bytes == null || bytes.length == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(bytes, offset, length, charset);
-        ObjectReader<T> objectReader = reader.getObjectReader(type);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into {@link JSONArray}
-     *
-     * @param text the JSON {@link String} to be parsed
-     */
-    @SuppressWarnings("unchecked")
-    static JSONArray parseArray(String text) {
-        if (text == null || text.length() == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-        ObjectReader<JSONArray> objectReader = reader.getObjectReader(JSONArray.class);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into {@link List}
-     *
-     * @param text the JSON {@link String} to be parsed
-     * @param type specify the {@link Type} to be converted
-     */
-    static <T> List<T> parseArray(String text, Type type) {
-        if (text == null || text.length() == 0) {
-            return null;
-        }
-        ParameterizedTypeImpl paramType = new ParameterizedTypeImpl(new Type[]{type}, null, List.class);
-        JSONReader reader = JSONReader.of(text);
-        return reader.read(paramType);
-    }
-
-    /**
-     * Parse JSON {@link String} into {@link List}
-     *
-     * @param text  the JSON {@link String} to be parsed
-     * @param types specify some {@link Type}s to be converted
-     */
-    static <T> List<T> parseArray(String text, Type[] types) {
-        if (text == null || text.length() == 0) {
-            return null;
-        }
-        List<T> array = new ArrayList<>(types.length);
-        JSONReader reader = JSONReader.of(text);
-
-        reader.startArray();
-        for (Type itemType : types) {
-            array.add(
-                    reader.read(itemType)
-            );
-        }
-        reader.endArray();
-
-        return array;
-    }
-
-    /**
-     * Serialize Java Object to JSON {@link String}
-     *
-     * @param object Java Object to be serialized into JSON {@link String}
-     */
-    static String toJSONString(Object object) {
-        try (JSONWriter writer = JSONWriter.of()) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.toString();
-        } catch (NullPointerException | NumberFormatException ex) {
-            throw new JSONException("toJSONString error", ex);
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param object   Java Object to be serialized into JSON {@link String}
-     * @param features features to be enabled in serialization
-     */
-    static String toJSONString(Object object, JSONWriter.Feature... features) {
-        JSONWriter.Context writeContext = new JSONWriter.Context(JSONFactory.defaultObjectWriterProvider, features);
-
-        boolean pretty = (writeContext.features & JSONWriter.Feature.PrettyFormat.mask) != 0;
-        JSONWriterUTF16 jsonWriter = JDKUtils.JVM_VERSION == 8 ? new JSONWriterUTF16JDK8(writeContext) : new JSONWriterUTF16(writeContext);
-
-        try (JSONWriter writer = pretty ?
-                new JSONWriterPretty(jsonWriter) : jsonWriter) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                writer.setRootObject(object);
-                Class<?> valueClass = object.getClass();
-
-                boolean fieldBased = (writeContext.features & JSONWriter.Feature.FieldBased.mask) != 0;
-                ObjectWriter<?> objectWriter = writeContext.provider.getObjectWriter(valueClass, valueClass, fieldBased);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.toString();
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param object   Java Object to be serialized into JSON {@link String}
-     * @param filters  specifies the filter to use in serialization
-     * @param features features to be enabled in serialization
-     */
-    static String toJSONString(Object object, Filter[] filters, JSONWriter.Feature... features) {
-        try (JSONWriter writer = JSONWriter.of(features)) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                writer.setRootObject(object);
-                if (filters != null && filters.length != 0) {
-                    writer.context.configFilter(filters);
-                }
-
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.toString();
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param object   Java Object to be serialized into JSON {@link String}
-     * @param filter   specify a filter to use in serialization
-     * @param features features to be enabled in serialization
-     */
-    static String toJSONString(Object object, Filter filter, JSONWriter.Feature... features) {
-        try (JSONWriter writer = JSONWriter.of(features)) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                writer.setRootObject(object);
-                if (filter != null) {
-                    writer.context.configFilter(filter);
-                }
-
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.toString();
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param object   Java Object to be serialized into JSON {@link String}
-     * @param format   the specified date format
-     * @param features features to be enabled in serialization
-     */
-    static String toJSONString(Object object, String format, JSONWriter.Feature... features) {
-        try (JSONWriter writer = JSONWriter.of(features)) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                writer.setRootObject(object);
-                writer.context.setDateFormat(format);
-
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.toString();
+    static <T> T parseObject(byte[] bytes, int offset, int length, Charset charset, Type type) {
+        if (bytes == null || bytes.length == 0) {
+            return null;
         }
+        JSONReader reader = JSONReader.of(bytes, offset, length, charset);
+        ObjectReader<T> objectReader = reader.getObjectReader(type);
+        return objectReader.readObject(reader, 0);
     }
 
     /**
-     * Serialize Java Object to JSON byte array
+     * Parse JSON {@link String} into {@link JSONArray}
      *
-     * @param object Java Object to be serialized into JSON byte array
+     * @param text the JSON {@link String} to be parsed
      */
-    static byte[] toJSONBytes(Object object) {
-        try (JSONWriter writer = JSONWriter.ofUTF8()) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.getBytes();
+    @SuppressWarnings("unchecked")
+    static JSONArray parseArray(String text) {
+        if (text == null || text.length() == 0) {
+            return null;
         }
+        JSONReader reader = JSONReader.of(text);
+        ObjectReader<JSONArray> objectReader = reader.getObjectReader(JSONArray.class);
+        return objectReader.readObject(reader, 0);
     }
 
     /**
-     * Serialize Java Object to JSON byte array
+     * Parse JSON {@link String} into {@link List}
      *
-     * @param object  Java Object to be serialized into JSON byte array
-     * @param filters specifies the filter to use in serialization
+     * @param text the JSON {@link String} to be parsed
+     * @param type specify the {@link Type} to be converted
      */
-    static byte[] toJSONBytes(Object object, Filter... filters) {
-        try (JSONWriter writer = JSONWriter.ofUTF8()) {
-            if (filters != null && filters.length != 0) {
-                writer.context.configFilter(filters);
-            }
-
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.getBytes();
+    static <T> List<T> parseArray(String text, Type type) {
+        if (text == null || text.length() == 0) {
+            return null;
         }
+        ParameterizedTypeImpl paramType = new ParameterizedTypeImpl(new Type[]{type}, null, List.class);
+        JSONReader reader = JSONReader.of(text);
+        return reader.read(paramType);
     }
 
     /**
-     * Serialize Java Object to JSON byte array with specified {@link JSONReader.Feature}s enabled
+     * Parse JSON {@link String} into {@link List}
      *
-     * @param object   Java Object to be serialized into JSON byte array
-     * @param features features to be enabled in serialization
+     * @param text  the JSON {@link String} to be parsed
+     * @param types specify some {@link Type}s to be converted
      */
-    static byte[] toJSONBytes(Object object, JSONWriter.Feature... features) {
-        try (JSONWriter writer = JSONWriter.ofUTF8(features)) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                writer.setRootObject(object);
+    static <T> List<T> parseArray(String text, Type[] types) {
+        if (text == null || text.length() == 0) {
+            return null;
+        }
+        List<T> array = new ArrayList<>(types.length);
+        JSONReader reader = JSONReader.of(text);
 
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.getBytes();
+        reader.startArray();
+        for (Type itemType : types) {
+            array.add(
+                    reader.read(itemType)
+            );
         }
+        reader.endArray();
+
+        return array;
     }
 
     /**
-     * Serialize Java Object to JSON byte array with specified {@link JSONReader.Feature}s enabled
+     * Parse JSON {@link String} into {@link JSONArray} or {@link JSONObject}
      *
-     * @param object   Java Object to be serialized into JSON byte array
-     * @param filters  specifies the filter to use in serialization
-     * @param features features to be enabled in serialization
+     * @param text the JSON {@link String} to be parsed
+     * @return Object
      */
-    static byte[] toJSONBytes(Object object, Filter[] filters, JSONWriter.Feature... features) {
-        try (JSONWriter writer = JSONWriter.ofUTF8(features)) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                writer.setRootObject(object);
-                if (filters != null && filters.length != 0) {
-                    writer.context.configFilter(filters);
-                }
-
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-            return writer.getBytes();
+    static Object parse(String text) {
+        if (text == null) {
+            return null;
         }
+        JSONReader reader = JSONReader.of(text);
+        ObjectReader<?> objectReader = reader.getObjectReader(Object.class);
+        return objectReader.readObject(reader, 0);
     }
 
     /**
-     * Serialize Java Object to JSON and write to {@link OutputStream} with specified {@link JSONReader.Feature}s enabled
+     * Parse JSON {@link String} into {@link JSONArray} or {@link JSONObject} with specified {@link JSONReader.Feature}s enabled
      *
-     * @param out      {@link OutputStream} to be written
-     * @param object   Java Object to be serialized into JSON
-     * @param features features to be enabled in serialization
-     * @throws JSONException if an I/O error occurs. In particular, a {@link JSONException} may be thrown if the output stream has been closed
+     * @param text     the JSON {@link String} to be parsed
+     * @param features features to be enabled in parsing
+     * @return Object
      */
-    static int writeTo(OutputStream out, Object object, JSONWriter.Feature... features) {
-        try (JSONWriter writer = JSONWriter.ofUTF8(features)) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                writer.setRootObject(object);
-
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-
-            return writer.flushTo(out);
-        } catch (IOException e) {
-            throw new JSONException(e.getMessage(), e);
+    static Object parse(String text, JSONReader.Feature... features) {
+        if (text == null) {
+            return null;
         }
+        JSONReader reader = JSONReader.of(text);
+        reader.context.config(features);
+        ObjectReader<?> objectReader = reader.getObjectReader(Object.class);
+        return objectReader.readObject(reader, 0);
     }
 
-    /**
-     * Serialize Java Object to JSON and write to {@link OutputStream} with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param out      {@link OutputStream} to be written
-     * @param object   Java Object to be serialized into JSON
-     * @param filters  specifies the filter to use in serialization
-     * @param features features to be enabled in serialization
-     * @throws JSONException if an I/O error occurs. In particular, a {@link JSONException} may be thrown if the output stream has been closed
-     */
-    static int writeTo(OutputStream out, Object object, Filter[] filters, JSONWriter.Feature... features) {
-        try (JSONWriter writer = JSONWriter.ofUTF8(features)) {
-            if (object == null) {
-                writer.writeNull();
-            } else {
-                writer.setRootObject(object);
-                if (filters != null && filters.length != 0) {
-                    writer.context.configFilter(filters);
-                }
-
-                Class<?> valueClass = object.getClass();
-                ObjectWriter<?> objectWriter = writer.getObjectWriter(valueClass, valueClass);
-                objectWriter.write(writer, object, null, null, 0);
-            }
-
-            return writer.flushTo(out);
-        } catch (IOException e) {
-            throw new JSONException(e.getMessage(), e);
-        }
+    static void mixIn(Class target, Class mixinSource) {
+        JSONFactory.defaultObjectWriterProvider.mixIn(target, mixinSource);
+        JSONFactory.getDefaultObjectReaderProvider().mixIn(target, mixinSource);
     }
 
     /**
-     * Verify the {@link String} is JSON Object
+     * Verify the {@link String} is JSON Array
      *
      * @param text the {@link String} to validate
      * @return T/F
      */
-    static boolean isValid(String text) {
+    static boolean isValidArray(String text) {
         if (text == null || text.length() == 0) {
             return false;
         }
         JSONReader jsonReader = JSONReader.of(text);
         try {
+            if (!jsonReader.isArray()) {
+                return false;
+            }
             jsonReader.skipValue();
         } catch (JSONException error) {
             return false;
@@ -609,16 +660,16 @@ public interface JSON {
     }
 
     /**
-     * Verify the {@link String} is JSON Array
+     * Verify the byte array is JSON Array
      *
-     * @param text the {@link String} to validate
+     * @param bytes the byte array to validate
      * @return T/F
      */
-    static boolean isValidArray(String text) {
-        if (text == null || text.length() == 0) {
+    static boolean isValidArray(byte[] bytes) {
+        if (bytes == null || bytes.length == 0) {
             return false;
         }
-        JSONReader jsonReader = JSONReader.of(text);
+        JSONReader jsonReader = JSONReader.of(bytes);
         try {
             if (!jsonReader.isArray()) {
                 return false;
@@ -631,16 +682,16 @@ public interface JSON {
     }
 
     /**
-     * Verify the byte array is JSON Object
+     * Verify the {@link String} is JSON Object
      *
-     * @param bytes the byte array to validate
+     * @param text the {@link String} to validate
      * @return T/F
      */
-    static boolean isValid(byte[] bytes) {
-        if (bytes == null || bytes.length == 0) {
+    static boolean isValid(String text) {
+        if (text == null || text.length() == 0) {
             return false;
         }
-        JSONReader jsonReader = JSONReader.of(bytes);
+        JSONReader jsonReader = JSONReader.of(text);
         try {
             jsonReader.skipValue();
         } catch (JSONException error) {
@@ -650,20 +701,17 @@ public interface JSON {
     }
 
     /**
-     * Verify the byte array is JSON Array
+     * Verify the byte array is JSON Object
      *
      * @param bytes the byte array to validate
      * @return T/F
      */
-    static boolean isValidArray(byte[] bytes) {
+    static boolean isValid(byte[] bytes) {
         if (bytes == null || bytes.length == 0) {
             return false;
         }
         JSONReader jsonReader = JSONReader.of(bytes);
         try {
-            if (!jsonReader.isArray()) {
-                return false;
-            }
             jsonReader.skipValue();
         } catch (JSONException error) {
             return false;
@@ -692,52 +740,4 @@ public interface JSON {
         }
         return true;
     }
-
-    /**
-     * Convert Java object order to {@link JSONArray} or {@link JSONObject}
-     *
-     * @param object Java Object to be converted
-     * @return Java Object
-     */
-    static Object toJSON(Object object) {
-        if (object == null) {
-            return null;
-        }
-        if (object instanceof JSONObject || object instanceof JSONArray) {
-            return object;
-        }
-
-        String str = JSON.toJSONString(object);
-        return JSON.parse(str);
-    }
-
-    /**
-     * Convert the Object to the target type
-     *
-     * @param object Java Object to be converted
-     * @param clazz  converted goal class
-     */
-    static <T> T toJavaObject(Object object, Class<T> clazz) {
-        if (object == null) {
-            return null;
-        }
-        if (object instanceof JSONObject) {
-            return ((JSONObject) object).toJavaObject(clazz);
-        }
-
-        return TypeUtils.cast(object, clazz);
-    }
-
-    static void mixIn(Class target, Class mixinSource) {
-        JSONFactory.defaultObjectWriterProvider.mixIn(target, mixinSource);
-        JSONFactory.getDefaultObjectReaderProvider().mixIn(target, mixinSource);
-    }
-
-    static boolean register(Type type, ObjectReader objectReader) {
-        return JSONFactory.getDefaultObjectReaderProvider().register(type, objectReader);
-    }
-
-    static boolean register(Type type, ObjectWriter objectReader) {
-        return JSONFactory.defaultObjectWriterProvider.register(type, objectReader);
-    }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./mvnw -V --no-transfer-progress -Pgen-javadoc -Pgen-dokka clean package -Dsurefire.useFile=false -Dmaven.test.skip=false -DfailIfNoTests=false || true

