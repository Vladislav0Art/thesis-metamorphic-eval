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
deleted file mode 100644
index b6a0ff2ce..000000000
--- a/core/src/main/java/com/alibaba/fastjson2/JSON.java
+++ /dev/null
@@ -1,743 +0,0 @@
-package com.alibaba.fastjson2;
-
-import com.alibaba.fastjson2.filter.Filter;
-import com.alibaba.fastjson2.reader.ObjectReader;
-import com.alibaba.fastjson2.util.JDKUtils;
-import com.alibaba.fastjson2.util.ParameterizedTypeImpl;
-import com.alibaba.fastjson2.util.TypeUtils;
-import com.alibaba.fastjson2.writer.ObjectWriter;
-
-import java.io.IOException;
-import java.io.OutputStream;
-import java.lang.reflect.Type;
-import java.nio.charset.Charset;
-import java.util.ArrayList;
-import java.util.List;
-
-public interface JSON {
-    /**
-     * FASTJSON2 version name
-     */
-    String VERSION = "2.0.2";
-
-    /**
-     * Parse JSON {@link String} into {@link JSONArray} or {@link JSONObject}
-     *
-     * @param text the JSON {@link String} to be parsed
-     * @return Object
-     */
-    static Object parse(String text) {
-        if (text == null) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-        ObjectReader<?> objectReader = reader.getObjectReader(Object.class);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into {@link JSONArray} or {@link JSONObject} with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param text     the JSON {@link String} to be parsed
-     * @param features features to be enabled in parsing
-     * @return Object
-     */
-    static Object parse(String text, JSONReader.Feature... features) {
-        if (text == null) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-        reader.context.config(features);
-        ObjectReader<?> objectReader = reader.getObjectReader(Object.class);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into {@link JSONObject}
-     *
-     * @param text the JSON {@link String} to be parsed
-     * @return JSONObject
-     */
-    @SuppressWarnings("unchecked")
-    static JSONObject parseObject(String text) {
-        if (text == null) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-        ObjectReader<JSONObject> objectReader = reader.getObjectReader(JSONObject.class);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse UTF8 encoded JSON byte array into {@link JSONObject}
-     *
-     * @param bytes UTF8 encoded JSON byte array to parse
-     * @return JSONObject
-     */
-    @SuppressWarnings("unchecked")
-    static JSONObject parseObject(byte[] bytes) {
-        if (bytes == null || bytes.length == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(bytes);
-        ObjectReader<JSONObject> objectReader = reader.getObjectReader(JSONObject.class);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into Java Object
-     *
-     * @param text  the JSON {@link String} to be parsed
-     * @param clazz specify the Class to be converted
-     * @return Class
-     */
-    @SuppressWarnings("unchecked")
-    static <T> T parseObject(String text, Class<T> clazz) {
-        if (text == null) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-        JSONReader.Context context = reader.context;
-
-        boolean fieldBased = (context.features & JSONReader.Feature.FieldBased.mask) != 0;
-        ObjectReader<T> objectReader = context.provider.getObjectReader(clazz, fieldBased);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into Java Object
-     *
-     * @param text the JSON {@link String} to be parsed
-     * @param type specify the {@link Type} to be converted
-     */
-    @SuppressWarnings("unchecked")
-    static <T> T parseObject(String text, Type type) {
-        if (text == null || text.length() == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-        ObjectReader<T> objectReader = reader.context.provider.getObjectReader(type);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into Java Object
-     *
-     * @param text          the JSON {@link String} to be parsed
-     * @param typeReference specify the {@link TypeReference} to be converted
-     */
-    @SuppressWarnings({"unchecked", "rawtypes"})
-    static <T> T parseObject(String text, TypeReference typeReference) {
-        if (text == null || text.length() == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-        ObjectReader<T> objectReader = reader.context.provider.getObjectReader(typeReference.getType());
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into a Java object with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param text     the JSON {@link String} to be parsed
-     * @param clazz    specify the Class to be converted
-     * @param features features to be enabled in parsing
-     */
-    @SuppressWarnings("unchecked")
-    static <T> T parseObject(String text, Class<T> clazz, JSONReader.Feature... features) {
-        if (text == null || text.length() == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-
-        JSONReader.Context context = reader.context;
-        context.config(features);
-        boolean fieldBased = (context.features & JSONReader.Feature.FieldBased.mask) != 0;
-
-        ObjectReader<T> objectReader = context.provider.getObjectReader(clazz, fieldBased);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into a Java object with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param text     the JSON {@link String} to be parsed
-     * @param clazz    specify the Class to be converted
-     * @param format   the specified date format
-     * @param features features to be enabled in parsing
-     */
-    @SuppressWarnings("unchecked")
-    static <T> T parseObject(String text, Class<T> clazz, String format, JSONReader.Feature... features) {
-        if (text == null || text.length() == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-
-        JSONReader.Context context = reader.context;
-        if (format != null) {
-            context.setUtilDateFormat(format);
-        }
-        context.config(features);
-
-        ObjectReader<T> objectReader = context.provider.getObjectReader(clazz);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse JSON {@link String} into a Java object with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param text     the JSON {@link String} to be parsed
-     * @param type     specify the {@link Type} to be converted
-     * @param features features to be enabled in parsing
-     */
-    @SuppressWarnings("unchecked")
-    static <T> T parseObject(String text, Type type, JSONReader.Feature... features) {
-        if (text == null || text.length() == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(text);
-        reader.context.config(features);
-        ObjectReader<T> objectReader = reader.getObjectReader(type);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse UTF8 encoded JSON byte array into a Java object
-     *
-     * @param bytes UTF8 encoded JSON byte array to parse
-     * @param type  specify the {@link Type} to be converted
-     */
-    @SuppressWarnings("unchecked")
-    static <T> T parseObject(byte[] bytes, Type type) {
-        if (bytes == null || bytes.length == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(bytes);
-        ObjectReader<T> objectReader = reader.getObjectReader(type);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse UTF8 encoded JSON byte array into a Java object
-     *
-     * @param bytes UTF8 encoded JSON byte array to parse
-     * @param clazz specify the Class to be converted
-     */
-    @SuppressWarnings("unchecked")
-    static <T> T parseObject(byte[] bytes, Class<T> clazz) {
-        if (bytes == null || bytes.length == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(bytes);
-        ObjectReader<T> objectReader = reader.getObjectReader(clazz);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parse UTF8 encoded JSON byte array into a Java object with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param bytes    UTF8 encoded JSON byte array to parse
-     * @param type     specify the {@link Type} to be converted
-     * @param features features to be enabled in parsing
-     */
-    @SuppressWarnings("unchecked")
-    static <T> T parseObject(byte[] bytes, Type type, JSONReader.Feature... features) {
-        if (bytes == null || bytes.length == 0) {
-            return null;
-        }
-        JSONReader reader = JSONReader.of(bytes);
-        reader.getContext().config(features);
-        ObjectReader<T> objectReader = reader.getObjectReader(type);
-        return objectReader.readObject(reader, 0);
-    }
-
-    /**
-     * Parses the JSON byte array of the specified {@link Charset} into a Java Object
-     *
-     * @param bytes   JSON byte array to parse
-     * @param offset  the index of the first byte to parse
-     * @param length  the number of bytes to parse
-     * @param charset specify {@link Charset} to parse
-     * @param type    specify the {@link Type} to be converted
-     * @throws IndexOutOfBoundsException If the offset and the length arguments index characters outside the bounds of the bytes array
-     */
-    @SuppressWarnings("unchecked")
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
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON byte array
-     *
-     * @param object Java Object to be serialized into JSON byte array
-     */
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
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON byte array
-     *
-     * @param object  Java Object to be serialized into JSON byte array
-     * @param filters specifies the filter to use in serialization
-     */
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
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON byte array with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param object   Java Object to be serialized into JSON byte array
-     * @param features features to be enabled in serialization
-     */
-    static byte[] toJSONBytes(Object object, JSONWriter.Feature... features) {
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
-            return writer.getBytes();
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON byte array with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param object   Java Object to be serialized into JSON byte array
-     * @param filters  specifies the filter to use in serialization
-     * @param features features to be enabled in serialization
-     */
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
-        }
-    }
-
-    /**
-     * Serialize Java Object to JSON and write to {@link OutputStream} with specified {@link JSONReader.Feature}s enabled
-     *
-     * @param out      {@link OutputStream} to be written
-     * @param object   Java Object to be serialized into JSON
-     * @param features features to be enabled in serialization
-     * @throws JSONException if an I/O error occurs. In particular, a {@link JSONException} may be thrown if the output stream has been closed
-     */
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
-        }
-    }
-
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
-    }
-
-    /**
-     * Verify the {@link String} is JSON Object
-     *
-     * @param text the {@link String} to validate
-     * @return T/F
-     */
-    static boolean isValid(String text) {
-        if (text == null || text.length() == 0) {
-            return false;
-        }
-        JSONReader jsonReader = JSONReader.of(text);
-        try {
-            jsonReader.skipValue();
-        } catch (JSONException error) {
-            return false;
-        }
-        return true;
-    }
-
-    /**
-     * Verify the {@link String} is JSON Array
-     *
-     * @param text the {@link String} to validate
-     * @return T/F
-     */
-    static boolean isValidArray(String text) {
-        if (text == null || text.length() == 0) {
-            return false;
-        }
-        JSONReader jsonReader = JSONReader.of(text);
-        try {
-            if (!jsonReader.isArray()) {
-                return false;
-            }
-            jsonReader.skipValue();
-        } catch (JSONException error) {
-            return false;
-        }
-        return true;
-    }
-
-    /**
-     * Verify the byte array is JSON Object
-     *
-     * @param bytes the byte array to validate
-     * @return T/F
-     */
-    static boolean isValid(byte[] bytes) {
-        if (bytes == null || bytes.length == 0) {
-            return false;
-        }
-        JSONReader jsonReader = JSONReader.of(bytes);
-        try {
-            jsonReader.skipValue();
-        } catch (JSONException error) {
-            return false;
-        }
-        return true;
-    }
-
-    /**
-     * Verify the byte array is JSON Array
-     *
-     * @param bytes the byte array to validate
-     * @return T/F
-     */
-    static boolean isValidArray(byte[] bytes) {
-        if (bytes == null || bytes.length == 0) {
-            return false;
-        }
-        JSONReader jsonReader = JSONReader.of(bytes);
-        try {
-            if (!jsonReader.isArray()) {
-                return false;
-            }
-            jsonReader.skipValue();
-        } catch (JSONException error) {
-            return false;
-        }
-        return true;
-    }
-
-    /**
-     * Verify the byte array is JSON Object
-     *
-     * @param bytes   the byte array to validate
-     * @param offset  the index of the first byte to validate
-     * @param length  the number of bytes to validate
-     * @param charset specify {@link Charset} to validate
-     * @return T/F
-     */
-    static boolean isValid(byte[] bytes, int offset, int length, Charset charset) {
-        if (bytes == null || bytes.length == 0) {
-            return false;
-        }
-        JSONReader jsonReader = JSONReader.of(bytes, offset, length, charset);
-        try {
-            jsonReader.skipValue();
-        } catch (JSONException error) {
-            return false;
-        }
-        return true;
-    }
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
-}
diff --git a/core/src/main/java/com/alibaba/fastjson2/JSONArray.java b/core/src/main/java/com/alibaba/fastjson2/JSONArray.java
index 66d8e9dd9..5a6a1d5ee 100644
--- a/core/src/main/java/com/alibaba/fastjson2/JSONArray.java
+++ b/core/src/main/java/com/alibaba/fastjson2/JSONArray.java
@@ -144,7 +144,7 @@ public class JSONArray extends ArrayList<Object> {
             return (String) value;
         }
 
-        return JSON.toJSONString(value);
+        return JsonMapper.toJsonString(value);
     }
 
     /**
diff --git a/core/src/main/java/com/alibaba/fastjson2/JSONB.java b/core/src/main/java/com/alibaba/fastjson2/JSONB.java
index f840ff72f..e42cde194 100644
--- a/core/src/main/java/com/alibaba/fastjson2/JSONB.java
+++ b/core/src/main/java/com/alibaba/fastjson2/JSONB.java
@@ -777,7 +777,7 @@ public interface JSONB {
     }
 
     static byte[] fromJSONString(String str) {
-        return JSONB.toBytes(JSON.parse(str));
+        return JSONB.toBytes(JsonMapper.parseJson(str));
     }
 
     static byte[] fromJSONBytes(byte[] jsonUtf8Bytes) {
diff --git a/core/src/main/java/com/alibaba/fastjson2/JSONObject.java b/core/src/main/java/com/alibaba/fastjson2/JSONObject.java
index 7ba110841..2c23a4c22 100644
--- a/core/src/main/java/com/alibaba/fastjson2/JSONObject.java
+++ b/core/src/main/java/com/alibaba/fastjson2/JSONObject.java
@@ -218,7 +218,7 @@ public class JSONObject extends LinkedHashMap<String, Object> implements Invocat
             return (String) value;
         }
 
-        return JSON.toJSONString(value);
+        return JsonMapper.toJsonString(value);
     }
 
     /**
@@ -928,7 +928,7 @@ public class JSONObject extends LinkedHashMap<String, Object> implements Invocat
             return (T) value;
         }
 
-        String json = JSON.toJSONString(value);
+        String json = JsonMapper.toJsonString(value);
         JSONReader jsonReader = JSONReader.of(json);
 
         ObjectReader objectReader = provider.getObjectReader(clazz);
@@ -1139,9 +1139,9 @@ public class JSONObject extends LinkedHashMap<String, Object> implements Invocat
     }
 
     /**
-     * See {@link JSON#parseObject} for details
+     * See {@link JsonMapper#parseJsonObject} for details
      */
     public static <T> T parseObject(String text, Class<T> clazz) {
-        return JSON.parseObject(text, clazz);
+        return JsonMapper.parseJsonObject(text, clazz);
     }
 }
diff --git a/core/src/main/java/com/alibaba/fastjson2/JSONPath.java b/core/src/main/java/com/alibaba/fastjson2/JSONPath.java
index 39e0b47ca..d3a7ee58a 100644
--- a/core/src/main/java/com/alibaba/fastjson2/JSONPath.java
+++ b/core/src/main/java/com/alibaba/fastjson2/JSONPath.java
@@ -2156,7 +2156,7 @@ public abstract class JSONPath {
                             throw new JSONException("TODO : " + jsonReader.ch);
                     }
 
-                    return JSON.toJSONString(val);
+                    return JsonMapper.toJsonString(val);
                 }
             }
             return null;
@@ -2490,7 +2490,7 @@ public abstract class JSONPath {
         public String extractScalar(JSONReader jsonReader) {
             Context ctx = new Context(this, null, segment, null);
             segment.accept(jsonReader, ctx);
-            return JSON.toJSONString(ctx.value);
+            return JsonMapper.toJsonString(ctx.value);
         }
     }
 
@@ -2693,7 +2693,7 @@ public abstract class JSONPath {
                 segment.accept(jsonReader, ctx);
             }
 
-            return JSON.toJSONString(ctx.value);
+            return JsonMapper.toJsonString(ctx.value);
         }
     }
 
diff --git a/core/src/main/java/com/alibaba/fastjson2/JSONReader.java b/core/src/main/java/com/alibaba/fastjson2/JSONReader.java
index af3a042cd..5be63a9ea 100644
--- a/core/src/main/java/com/alibaba/fastjson2/JSONReader.java
+++ b/core/src/main/java/com/alibaba/fastjson2/JSONReader.java
@@ -919,7 +919,7 @@ public abstract class JSONReader implements Closeable {
     public void readString(ValueConsumer consumer, boolean quoted) {
         String str = readString(); //
         if (quoted) {
-            consumer.accept(JSON.toJSONString(str));
+            consumer.accept(JsonMapper.toJsonString(str));
         } else {
             consumer.accept(str);
         }
diff --git a/core/src/main/java/com/alibaba/fastjson2/JsonMapper.java b/core/src/main/java/com/alibaba/fastjson2/JsonMapper.java
new file mode 100644
index 000000000..74419c0dd
--- /dev/null
+++ b/core/src/main/java/com/alibaba/fastjson2/JsonMapper.java
@@ -0,0 +1,743 @@
+package com.alibaba.fastjson2;
+
+import com.alibaba.fastjson2.filter.Filter;
+import com.alibaba.fastjson2.reader.ObjectReader;
+import com.alibaba.fastjson2.util.JDKUtils;
+import com.alibaba.fastjson2.util.ParameterizedTypeImpl;
+import com.alibaba.fastjson2.util.TypeUtils;
+import com.alibaba.fastjson2.writer.ObjectWriter;
+
+import java.io.IOException;
+import java.io.OutputStream;
+import java.lang.reflect.Type;
+import java.nio.charset.Charset;
+import java.util.ArrayList;
+import java.util.List;
+
+public interface JsonMapper {
+    /**
+     * FASTJSON2 version name
+     */
+    String VERSION = "2.0.2";
+
+    /**
+     * Parse JSON {@link String} into {@link JSONArray} or {@link JSONObject}
+     *
+     * @param jsonContent the JSON {@link String} to be parsed
+     * @return Object
+     */
+    static Object parseJson(String jsonContent) {
+        if (jsonContent == null) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        ObjectReader<?> valueDeserializer = jsonParser.getObjectReader(Object.class);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into {@link JSONArray} or {@link JSONObject} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param jsonContent     the JSON {@link String} to be parsed
+     * @param options features to be enabled in parsing
+     * @return Object
+     */
+    static Object parseJson(String jsonContent, JSONReader.Feature... options) {
+        if (jsonContent == null) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        jsonParser.context.config(options);
+        ObjectReader<?> valueDeserializer = jsonParser.getObjectReader(Object.class);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into {@link JSONObject}
+     *
+     * @param jsonContent the JSON {@link String} to be parsed
+     * @return JSONObject
+     */
+    @SuppressWarnings("unchecked")
+    static JSONObject parseJsonObject(String jsonContent) {
+        if (jsonContent == null) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        ObjectReader<JSONObject> valueDeserializer = jsonParser.getObjectReader(JSONObject.class);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse UTF8 encoded JSON byte array into {@link JSONObject}
+     *
+     * @param binaryPayload UTF8 encoded JSON byte array to parse
+     * @return JSONObject
+     */
+    @SuppressWarnings("unchecked")
+    static JSONObject parseJsonObject(byte[] binaryPayload) {
+        if (binaryPayload == null || binaryPayload.length == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(binaryPayload);
+        ObjectReader<JSONObject> valueDeserializer = jsonParser.getObjectReader(JSONObject.class);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into Java Object
+     *
+     * @param jsonContent  the JSON {@link String} to be parsed
+     * @param targetClass specify the Class to be converted
+     * @return Class
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(String jsonContent, Class<T> targetClass) {
+        if (jsonContent == null) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        JSONReader.Context parseEnv = jsonParser.context;
+
+        boolean useFieldAccess = (parseEnv.features & JSONReader.Feature.FieldBased.mask) != 0;
+        ObjectReader<T> valueDeserializer = parseEnv.provider.getObjectReader(targetClass, useFieldAccess);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into Java Object
+     *
+     * @param jsonContent the JSON {@link String} to be parsed
+     * @param target specify the {@link Type} to be converted
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(String jsonContent, Type target) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        ObjectReader<T> valueDeserializer = jsonParser.context.provider.getObjectReader(target);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into Java Object
+     *
+     * @param jsonContent          the JSON {@link String} to be parsed
+     * @param genericRef specify the {@link TypeReference} to be converted
+     */
+    @SuppressWarnings({"unchecked", "rawtypes"})
+    static <T> T parseJsonObject(String jsonContent, TypeReference genericRef) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        ObjectReader<T> valueDeserializer = jsonParser.context.provider.getObjectReader(genericRef.getType());
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into a Java object with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param jsonContent     the JSON {@link String} to be parsed
+     * @param targetClass    specify the Class to be converted
+     * @param options features to be enabled in parsing
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(String jsonContent, Class<T> targetClass, JSONReader.Feature... options) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+
+        JSONReader.Context parseEnv = jsonParser.context;
+        parseEnv.config(options);
+        boolean useFieldAccess = (parseEnv.features & JSONReader.Feature.FieldBased.mask) != 0;
+
+        ObjectReader<T> valueDeserializer = parseEnv.provider.getObjectReader(targetClass, useFieldAccess);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into a Java object with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param jsonContent     the JSON {@link String} to be parsed
+     * @param targetClass    specify the Class to be converted
+     * @param notation   the specified date format
+     * @param options features to be enabled in parsing
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(String jsonContent, Class<T> targetClass, String notation, JSONReader.Feature... options) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+
+        JSONReader.Context parseEnv = jsonParser.context;
+        if (notation != null) {
+            parseEnv.setUtilDateFormat(notation);
+        }
+        parseEnv.config(options);
+
+        ObjectReader<T> valueDeserializer = parseEnv.provider.getObjectReader(targetClass);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into a Java object with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param jsonContent     the JSON {@link String} to be parsed
+     * @param target     specify the {@link Type} to be converted
+     * @param options features to be enabled in parsing
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(String jsonContent, Type target, JSONReader.Feature... options) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        jsonParser.context.config(options);
+        ObjectReader<T> valueDeserializer = jsonParser.getObjectReader(target);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse UTF8 encoded JSON byte array into a Java object
+     *
+     * @param binaryPayload UTF8 encoded JSON byte array to parse
+     * @param target  specify the {@link Type} to be converted
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(byte[] binaryPayload, Type target) {
+        if (binaryPayload == null || binaryPayload.length == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(binaryPayload);
+        ObjectReader<T> valueDeserializer = jsonParser.getObjectReader(target);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse UTF8 encoded JSON byte array into a Java object
+     *
+     * @param binaryPayload UTF8 encoded JSON byte array to parse
+     * @param targetClass specify the Class to be converted
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(byte[] binaryPayload, Class<T> targetClass) {
+        if (binaryPayload == null || binaryPayload.length == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(binaryPayload);
+        ObjectReader<T> valueDeserializer = jsonParser.getObjectReader(targetClass);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse UTF8 encoded JSON byte array into a Java object with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param binaryPayload    UTF8 encoded JSON byte array to parse
+     * @param target     specify the {@link Type} to be converted
+     * @param options features to be enabled in parsing
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(byte[] binaryPayload, Type target, JSONReader.Feature... options) {
+        if (binaryPayload == null || binaryPayload.length == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(binaryPayload);
+        jsonParser.getContext().config(options);
+        ObjectReader<T> valueDeserializer = jsonParser.getObjectReader(target);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parses the JSON byte array of the specified {@link Charset} into a Java Object
+     *
+     * @param binaryPayload   JSON byte array to parse
+     * @param startIndex  the index of the first byte to parse
+     * @param size  the number of bytes to parse
+     * @param encoding specify {@link Charset} to parse
+     * @param target    specify the {@link Type} to be converted
+     * @throws IndexOutOfBoundsException If the offset and the length arguments index characters outside the bounds of the bytes array
+     */
+    @SuppressWarnings("unchecked")
+    static <T> T parseJsonObject(byte[] binaryPayload, int startIndex, int size, Charset encoding, Type target) {
+        if (binaryPayload == null || binaryPayload.length == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(binaryPayload, startIndex, size, encoding);
+        ObjectReader<T> valueDeserializer = jsonParser.getObjectReader(target);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into {@link JSONArray}
+     *
+     * @param jsonContent the JSON {@link String} to be parsed
+     */
+    @SuppressWarnings("unchecked")
+    static JSONArray parseJsonArray(String jsonContent) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return null;
+        }
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        ObjectReader<JSONArray> valueDeserializer = jsonParser.getObjectReader(JSONArray.class);
+        return valueDeserializer.readObject(jsonParser, 0);
+    }
+
+    /**
+     * Parse JSON {@link String} into {@link List}
+     *
+     * @param jsonContent the JSON {@link String} to be parsed
+     * @param target specify the {@link Type} to be converted
+     */
+    static <T> List<T> parseJsonArray(String jsonContent, Type target) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return null;
+        }
+        ParameterizedTypeImpl parameterizedSig = new ParameterizedTypeImpl(new Type[]{target}, null, List.class);
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+        return jsonParser.read(parameterizedSig);
+    }
+
+    /**
+     * Parse JSON {@link String} into {@link List}
+     *
+     * @param jsonContent  the JSON {@link String} to be parsed
+     * @param classArray specify some {@link Type}s to be converted
+     */
+    static <T> List<T> parseJsonArray(String jsonContent, Type[] classArray) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return null;
+        }
+        List<T> list = new ArrayList<>(classArray.length);
+        JSONReader jsonParser = JSONReader.of(jsonContent);
+
+        jsonParser.startArray();
+        for (Type elementClass : classArray) {
+            list.add(
+                    jsonParser.read(elementClass)
+            );
+        }
+        jsonParser.endArray();
+
+        return list;
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String}
+     *
+     * @param value Java Object to be serialized into JSON {@link String}
+     */
+    static String toJsonString(Object value) {
+        try (JSONWriter outputStream = JSONWriter.of()) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.toString();
+        } catch (NullPointerException | NumberFormatException cause) {
+            throw new JSONException("toJSONString error", cause);
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param value   Java Object to be serialized into JSON {@link String}
+     * @param options features to be enabled in serialization
+     */
+    static String toJsonString(Object value, JSONWriter.Feature... options) {
+        JSONWriter.Context outputContext = new JSONWriter.Context(JSONFactory.defaultObjectWriterProvider, options);
+
+        boolean formatted = (outputContext.features & JSONWriter.Feature.PrettyFormat.mask) != 0;
+        JSONWriterUTF16 jsonOutput = JDKUtils.JVM_VERSION == 8 ? new JSONWriterUTF16JDK8(outputContext) : new JSONWriterUTF16(outputContext);
+
+        try (JSONWriter outputStream = formatted ?
+                new JSONWriterPretty(jsonOutput) : jsonOutput) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                outputStream.setRootObject(value);
+                Class<?> targetClass = value.getClass();
+
+                boolean useFieldAccess = (outputContext.features & JSONWriter.Feature.FieldBased.mask) != 0;
+                ObjectWriter<?> serializer = outputContext.provider.getObjectWriter(targetClass, targetClass, useFieldAccess);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.toString();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param value   Java Object to be serialized into JSON {@link String}
+     * @param filterList  specifies the filter to use in serialization
+     * @param options features to be enabled in serialization
+     */
+    static String toJsonString(Object value, Filter[] filterList, JSONWriter.Feature... options) {
+        try (JSONWriter outputStream = JSONWriter.of(options)) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                outputStream.setRootObject(value);
+                if (filterList != null && filterList.length != 0) {
+                    outputStream.context.configFilter(filterList);
+                }
+
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.toString();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param value   Java Object to be serialized into JSON {@link String}
+     * @param criterion   specify a filter to use in serialization
+     * @param options features to be enabled in serialization
+     */
+    static String toJsonString(Object value, Filter criterion, JSONWriter.Feature... options) {
+        try (JSONWriter outputStream = JSONWriter.of(options)) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                outputStream.setRootObject(value);
+                if (criterion != null) {
+                    outputStream.context.configFilter(criterion);
+                }
+
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.toString();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON {@link String} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param value   Java Object to be serialized into JSON {@link String}
+     * @param notation   the specified date format
+     * @param options features to be enabled in serialization
+     */
+    static String toJsonString(Object value, String notation, JSONWriter.Feature... options) {
+        try (JSONWriter outputStream = JSONWriter.of(options)) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                outputStream.setRootObject(value);
+                outputStream.context.setDateFormat(notation);
+
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.toString();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON byte array
+     *
+     * @param value Java Object to be serialized into JSON byte array
+     */
+    static byte[] toJsonBytes(Object value) {
+        try (JSONWriter outputStream = JSONWriter.ofUTF8()) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.getBytes();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON byte array
+     *
+     * @param value  Java Object to be serialized into JSON byte array
+     * @param filterList specifies the filter to use in serialization
+     */
+    static byte[] toJsonBytes(Object value, Filter... filterList) {
+        try (JSONWriter outputStream = JSONWriter.ofUTF8()) {
+            if (filterList != null && filterList.length != 0) {
+                outputStream.context.configFilter(filterList);
+            }
+
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.getBytes();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON byte array with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param value   Java Object to be serialized into JSON byte array
+     * @param options features to be enabled in serialization
+     */
+    static byte[] toJsonBytes(Object value, JSONWriter.Feature... options) {
+        try (JSONWriter outputStream = JSONWriter.ofUTF8(options)) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                outputStream.setRootObject(value);
+
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.getBytes();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON byte array with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param value   Java Object to be serialized into JSON byte array
+     * @param filterList  specifies the filter to use in serialization
+     * @param options features to be enabled in serialization
+     */
+    static byte[] toJsonBytes(Object value, Filter[] filterList, JSONWriter.Feature... options) {
+        try (JSONWriter outputStream = JSONWriter.ofUTF8(options)) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                outputStream.setRootObject(value);
+                if (filterList != null && filterList.length != 0) {
+                    outputStream.context.configFilter(filterList);
+                }
+
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+            return outputStream.getBytes();
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON and write to {@link OutputStream} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param destinationStream      {@link OutputStream} to be written
+     * @param value   Java Object to be serialized into JSON
+     * @param options features to be enabled in serialization
+     * @throws JSONException if an I/O error occurs. In particular, a {@link JSONException} may be thrown if the output stream has been closed
+     */
+    static int writeToOutputStream(OutputStream destinationStream, Object value, JSONWriter.Feature... options) {
+        try (JSONWriter outputStream = JSONWriter.ofUTF8(options)) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                outputStream.setRootObject(value);
+
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+
+            return outputStream.flushTo(destinationStream);
+        } catch (IOException ioException) {
+            throw new JSONException(ioException.getMessage(), ioException);
+        }
+    }
+
+    /**
+     * Serialize Java Object to JSON and write to {@link OutputStream} with specified {@link JSONReader.Feature}s enabled
+     *
+     * @param destinationStream      {@link OutputStream} to be written
+     * @param value   Java Object to be serialized into JSON
+     * @param filterList  specifies the filter to use in serialization
+     * @param options features to be enabled in serialization
+     * @throws JSONException if an I/O error occurs. In particular, a {@link JSONException} may be thrown if the output stream has been closed
+     */
+    static int writeToOutputStream(OutputStream destinationStream, Object value, Filter[] filterList, JSONWriter.Feature... options) {
+        try (JSONWriter outputStream = JSONWriter.ofUTF8(options)) {
+            if (value == null) {
+                outputStream.writeNull();
+            } else {
+                outputStream.setRootObject(value);
+                if (filterList != null && filterList.length != 0) {
+                    outputStream.context.configFilter(filterList);
+                }
+
+                Class<?> targetClass = value.getClass();
+                ObjectWriter<?> serializer = outputStream.getObjectWriter(targetClass, targetClass);
+                serializer.write(outputStream, value, null, null, 0);
+            }
+
+            return outputStream.flushTo(destinationStream);
+        } catch (IOException ioException) {
+            throw new JSONException(ioException.getMessage(), ioException);
+        }
+    }
+
+    /**
+     * Verify the {@link String} is JSON Object
+     *
+     * @param jsonContent the {@link String} to validate
+     * @return T/F
+     */
+    static boolean isValid(String jsonContent) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return false;
+        }
+        JSONReader streamReader = JSONReader.of(jsonContent);
+        try {
+            streamReader.skipValue();
+        } catch (JSONException jsonException) {
+            return false;
+        }
+        return true;
+    }
+
+    /**
+     * Verify the {@link String} is JSON Array
+     *
+     * @param jsonContent the {@link String} to validate
+     * @return T/F
+     */
+    static boolean isValidArray(String jsonContent) {
+        if (jsonContent == null || jsonContent.length() == 0) {
+            return false;
+        }
+        JSONReader streamReader = JSONReader.of(jsonContent);
+        try {
+            if (!streamReader.isArray()) {
+                return false;
+            }
+            streamReader.skipValue();
+        } catch (JSONException jsonException) {
+            return false;
+        }
+        return true;
+    }
+
+    /**
+     * Verify the byte array is JSON Object
+     *
+     * @param binaryPayload the byte array to validate
+     * @return T/F
+     */
+    static boolean isValid(byte[] binaryPayload) {
+        if (binaryPayload == null || binaryPayload.length == 0) {
+            return false;
+        }
+        JSONReader streamReader = JSONReader.of(binaryPayload);
+        try {
+            streamReader.skipValue();
+        } catch (JSONException jsonException) {
+            return false;
+        }
+        return true;
+    }
+
+    /**
+     * Verify the byte array is JSON Array
+     *
+     * @param binaryPayload the byte array to validate
+     * @return T/F
+     */
+    static boolean isValidArray(byte[] binaryPayload) {
+        if (binaryPayload == null || binaryPayload.length == 0) {
+            return false;
+        }
+        JSONReader streamReader = JSONReader.of(binaryPayload);
+        try {
+            if (!streamReader.isArray()) {
+                return false;
+            }
+            streamReader.skipValue();
+        } catch (JSONException jsonException) {
+            return false;
+        }
+        return true;
+    }
+
+    /**
+     * Verify the byte array is JSON Object
+     *
+     * @param binaryPayload   the byte array to validate
+     * @param startIndex  the index of the first byte to validate
+     * @param size  the number of bytes to validate
+     * @param encoding specify {@link Charset} to validate
+     * @return T/F
+     */
+    static boolean isValid(byte[] binaryPayload, int startIndex, int size, Charset encoding) {
+        if (binaryPayload == null || binaryPayload.length == 0) {
+            return false;
+        }
+        JSONReader streamReader = JSONReader.of(binaryPayload, startIndex, size, encoding);
+        try {
+            streamReader.skipValue();
+        } catch (JSONException jsonException) {
+            return false;
+        }
+        return true;
+    }
+
+    /**
+     * Convert Java object order to {@link JSONArray} or {@link JSONObject}
+     *
+     * @param value Java Object to be converted
+     * @return Java Object
+     */
+    static Object toJson(Object value) {
+        if (value == null) {
+            return null;
+        }
+        if (value instanceof JSONObject || value instanceof JSONArray) {
+            return value;
+        }
+
+        String text = JsonMapper.toJsonString(value);
+        return JsonMapper.parseJson(text);
+    }
+
+    /**
+     * Convert the Object to the target type
+     *
+     * @param value Java Object to be converted
+     * @param targetClass  converted goal class
+     */
+    static <T> T convertToJavaObject(Object value, Class<T> targetClass) {
+        if (value == null) {
+            return null;
+        }
+        if (value instanceof JSONObject) {
+            return ((JSONObject) value).toJavaObject(targetClass);
+        }
+
+        return TypeUtils.cast(value, targetClass);
+    }
+
+    static void addMixIn(Class destinationClass, Class sourceClass) {
+        JSONFactory.defaultObjectWriterProvider.mixIn(destinationClass, sourceClass);
+        JSONFactory.getDefaultObjectReaderProvider().mixIn(destinationClass, sourceClass);
+    }
+
+    static boolean registerObjectReader(Type target, ObjectReader valueDeserializer) {
+        return JSONFactory.getDefaultObjectReaderProvider().register(target, valueDeserializer);
+    }
+
+    static boolean registerObjectReader(Type target, ObjectWriter valueDeserializer) {
+        return JSONFactory.defaultObjectWriterProvider.register(target, valueDeserializer);
+    }
+}
diff --git a/core/src/main/java/com/alibaba/fastjson2/TypeReference.java b/core/src/main/java/com/alibaba/fastjson2/TypeReference.java
index ee7e6b582..75217ded0 100644
--- a/core/src/main/java/com/alibaba/fastjson2/TypeReference.java
+++ b/core/src/main/java/com/alibaba/fastjson2/TypeReference.java
@@ -71,7 +71,7 @@ public abstract class TypeReference<T> {
     }
 
     /**
-     * See {@link JSON#parseObject} for details
+     * See {@link JsonMapper#parseJsonObject} for details
      *
      * <pre>{@code String text = "{\"id\":1,\"name\":\"kraity\"}";
      *
@@ -82,7 +82,7 @@ public abstract class TypeReference<T> {
      * @since 2.0.2
      */
     public T parseObject(String text) {
-        return JSON.parseObject(text, type);
+        return JsonMapper.parseJsonObject(text, type);
     }
 
     /**
@@ -98,7 +98,7 @@ public abstract class TypeReference<T> {
     }
 
     /**
-     * See {@link JSON#parseArray} for details
+     * See {@link JsonMapper#parseJsonArray} for details
      *
      * <pre>{@code String text = "[{\"id\":1,\"name\":\"kraity\"}]";
      *
@@ -109,7 +109,7 @@ public abstract class TypeReference<T> {
      * @since 2.0.2
      */
     public List<T> parseArray(String text) {
-        return JSON.parseArray(text, type);
+        return JsonMapper.parseJsonArray(text, type);
     }
 
     /**
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderDateField.java b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderDateField.java
index 7c7c01e65..7b13b7ba8 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderDateField.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/FieldReaderDateField.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.reader;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONException;
 import com.alibaba.fastjson2.JSONReader;
 
@@ -72,7 +72,7 @@ final class FieldReaderDateField<T> extends FieldReaderObjectField<T> {
     public void accept(T object, Object value) {
         if (value instanceof String) {
             JSONReader jsonReader = JSONReader.of(
-                    JSON.toJSONString(value));
+                    JsonMapper.toJsonString(value));
             value = getObjectReader(jsonReader)
                     .readObject(jsonReader);
         }
diff --git a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java
index 89d1d3b7f..1b9c41ae7 100644
--- a/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java
+++ b/core/src/main/java/com/alibaba/fastjson2/reader/ObjectReaderProvider.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.reader;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONException;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.JSONReader;
@@ -196,7 +196,7 @@ public class ObjectReaderProvider {
 
     public void registerIfAbsent(long hashCode, ObjectReader objectReader) {
         ClassLoader tcl = Thread.currentThread().getContextClassLoader();
-        if (tcl != null && tcl != JSON.class.getClassLoader()) {
+        if (tcl != null && tcl != JsonMapper.class.getClassLoader()) {
             int tclHash = System.identityHashCode(tcl);
             ConcurrentHashMap<Long, ObjectReader> tclHashCache = tclHashCaches.get(tclHash);
             if (tclHashCache == null) {
@@ -280,7 +280,7 @@ public class ObjectReaderProvider {
 
         ObjectReader objectReader = null;
         ClassLoader tcl = Thread.currentThread().getContextClassLoader();
-        if (tcl != null && tcl != JSON.class.getClassLoader()) {
+        if (tcl != null && tcl != JsonMapper.class.getClassLoader()) {
             int tclHash = System.identityHashCode(tcl);
             ConcurrentHashMap<Long, ObjectReader> tclHashCache = tclHashCaches.get(tclHash);
             if (tclHashCache != null) {
diff --git a/core/src/main/java/com/alibaba/fastjson2/util/DynamicClassLoader.java b/core/src/main/java/com/alibaba/fastjson2/util/DynamicClassLoader.java
index fbea59001..4daaf4d14 100644
--- a/core/src/main/java/com/alibaba/fastjson2/util/DynamicClassLoader.java
+++ b/core/src/main/java/com/alibaba/fastjson2/util/DynamicClassLoader.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.util;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.filter.NameFilter;
@@ -28,8 +28,8 @@ public class DynamicClassLoader extends ClassLoader {
     private static Map<String, Class<?>> classMapping = new HashMap<String, Class<?>>();
 
     static {
-        FASTJSON_PACKAGE = JSON.class.getPackage().getName() + ".";
-        FASTJSON_CLASSLOADER = JSON.class.getClassLoader();
+        FASTJSON_PACKAGE = JsonMapper.class.getPackage().getName() + ".";
+        FASTJSON_CLASSLOADER = JsonMapper.class.getClassLoader();
 
         Class[] classes = new Class[]{
                 Object.class,
diff --git a/core/src/main/java/com/alibaba/fastjson2/util/TypeUtils.java b/core/src/main/java/com/alibaba/fastjson2/util/TypeUtils.java
index 439b9ff4d..b695984fa 100644
--- a/core/src/main/java/com/alibaba/fastjson2/util/TypeUtils.java
+++ b/core/src/main/java/com/alibaba/fastjson2/util/TypeUtils.java
@@ -158,7 +158,7 @@ public class TypeUtils {
         }
 
         if (targetClass == String.class) {
-            return (T) JSON.toJSONString(obj);
+            return (T) JsonMapper.toJsonString(obj);
         }
 
         ObjectReaderProvider provider = JSONFactory.getDefaultObjectReaderProvider();
@@ -184,7 +184,7 @@ public class TypeUtils {
                 jsonReader = JSONReader.of(json);
             } else {
                 jsonReader = JSONReader.of(
-                        JSON.toJSONString(json));
+                        JsonMapper.toJsonString(json));
             }
 
             ObjectReader objectReader = JSONFactory
@@ -948,7 +948,7 @@ public class TypeUtils {
         }
 
         try {
-            return JSON.class.getClassLoader().loadClass(className);
+            return JsonMapper.class.getClassLoader().loadClass(className);
         } catch (ClassNotFoundException ignored) {
 
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/JSONArrayTest.java
index 19602f46d..fd4caf684 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONArrayTest.java
@@ -45,7 +45,7 @@ public class JSONArrayTest {
         array.add(Collections.singletonMap("v0000", 101));
         Integer1 obj = array.getObject(0, Integer1.class);
         assertNotNull(obj);
-        assertEquals("{\"v0000\":101}", JSON.toJSONString(obj));
+        assertEquals("{\"v0000\":101}", JsonMapper.toJsonString(obj));
 
         List<Long1> list = array.toJavaObject(new TypeReference<List<Long1>>(){}.getType());
         Long1 long1 = list.get(0);
@@ -60,7 +60,7 @@ public class JSONArrayTest {
                 , new TypeReference<List<Integer1>>(){}.getType());
         assertNotNull(list);
         assertEquals(Integer1.class, list.get(0).getClass());
-        assertEquals("[{}]", JSON.toJSONString(list));
+        assertEquals("[{}]", JsonMapper.toJsonString(list));
     }
 
     @Test
@@ -71,7 +71,7 @@ public class JSONArrayTest {
                 0, new TypeReference<Map<String, Integer1>>(){}.getType());
         assertNotNull(map);
         assertEquals(Integer1.class, map.get("val").getClass());
-        assertEquals("{\"val\":{}}", JSON.toJSONString(map));
+        assertEquals("{\"val\":{}}", JsonMapper.toJsonString(map));
     }
 
     @Test
@@ -157,7 +157,7 @@ public class JSONArrayTest {
     @Test
     public void read() {
         String str = "[123]";
-        JSONArray jsonArray = JSON.parseArray(str);
+        JSONArray jsonArray = JsonMapper.parseJsonArray(str);
         assertEquals(123, jsonArray.getIntValue(0));
         assertEquals(123L, jsonArray.getLongValue(0));
         assertEquals("123", jsonArray.getString(0));
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONBTest.java b/core/src/test/java/com/alibaba/fastjson2/JSONBTest.java
index e88140b82..dfca413af 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONBTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONBTest.java
@@ -918,7 +918,7 @@ public class JSONBTest {
         ByteArrayOutputStream out = new ByteArrayOutputStream();
         JSONB.writeTo(out, Collections.singleton(1));
         assertEquals("[1]"
-                , JSON.toJSONString(JSONB.parse(out.toByteArray())));
+                , JsonMapper.toJsonString(JSONB.parse(out.toByteArray())));
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONBTest4.java b/core/src/test/java/com/alibaba/fastjson2/JSONBTest4.java
index f3770f4e2..408966189 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONBTest4.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONBTest4.java
@@ -33,7 +33,7 @@ public class JSONBTest4 {
 
     @Test
     public void test_1() {
-        JSONObject object = JSON.parseObject(str1);
+        JSONObject object = JsonMapper.parseJsonObject(str1);
         JSONObject object2 = JSONB
                 .parseObject(
                         JSONB.fromJSONString(str1));
@@ -52,7 +52,7 @@ public class JSONBTest4 {
 
     @Test
     public void test_2() {
-        JSONObject object = JSON.parseObject(str2);
+        JSONObject object = JsonMapper.parseJsonObject(str2);
         JSONObject object2 = JSONB
                 .parseObject(
                         JSONB.fromJSONString(str2));
@@ -93,7 +93,7 @@ public class JSONBTest4 {
         assertEquals(expected
                 , path
                         .eval(
-                                JSON.parseObject(str2))
+                                JsonMapper.parseJsonObject(str2))
                         .toString());
     }
 
@@ -121,7 +121,7 @@ public class JSONBTest4 {
         assertEquals(expected
                 , path
                         .eval(
-                                JSON.parseObject(str2))
+                                JsonMapper.parseJsonObject(str2))
                         .toString());
     }
 
@@ -149,7 +149,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -178,7 +178,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -207,7 +207,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -236,7 +236,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -265,7 +265,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -294,7 +294,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -323,7 +323,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -352,7 +352,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -381,7 +381,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -410,7 +410,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -439,7 +439,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -468,7 +468,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -497,7 +497,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -526,7 +526,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -555,7 +555,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -585,7 +585,7 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
@@ -614,14 +614,14 @@ public class JSONBTest4 {
         assertEquals(
                 expected
                 , path.eval(
-                        JSON.parseObject(str2)
+                        JsonMapper.parseJsonObject(str2)
                 ).toString()
         );
     }
 
     @Test
     public void test_3() {
-        JSONObject object = JSON.parseObject(str3);
+        JSONObject object = JsonMapper.parseJsonObject(str3);
         JSONObject object2 = JSONB
                 .parseObject(
                         JSONB.fromJSONString(str3));
@@ -687,7 +687,7 @@ public class JSONBTest4 {
         assertEquals("[\"iPhone\"]"
                 , path
                         .eval(
-                                JSON.parseObject(str3))
+                                JsonMapper.parseJsonObject(str3))
                         .toString());
     }
 
@@ -717,7 +717,7 @@ public class JSONBTest4 {
         assertEquals("[\"iPhone\",\"home\"]"
                 , path
                         .eval(
-                                JSON.parseObject(str3))
+                                JsonMapper.parseJsonObject(str3))
                         .toString());
     }
 
@@ -744,7 +744,7 @@ public class JSONBTest4 {
         assertEquals("[\"iPhone\",\"home\"]"
                 , path
                         .eval(
-                                JSON.parseObject(str3))
+                                JsonMapper.parseJsonObject(str3))
                         .toString());
     }
 
@@ -796,7 +796,7 @@ public class JSONBTest4 {
         assertEquals("[\"iPhone\",\"0123-4567-8888\"]"
                 , path
                         .eval(
-                                JSON.parseObject(str3))
+                                JsonMapper.parseJsonObject(str3))
                         .toString());
     }
 
@@ -825,7 +825,7 @@ public class JSONBTest4 {
         assertEquals("[\"home\"]"
                 , path
                         .eval(
-                                JSON.parseObject(str3))
+                                JsonMapper.parseJsonObject(str3))
                         .toString());
     }
 
@@ -854,7 +854,7 @@ public class JSONBTest4 {
         assertEquals(expected
                 , path
                         .eval(
-                                JSON.parseObject(str3))
+                                JsonMapper.parseJsonObject(str3))
                         .toString());
     }
 
@@ -864,7 +864,7 @@ public class JSONBTest4 {
         String expected = "\"iPhone\"";
 
         assertEquals(expected,
-                JSON.toJSONString(
+                JsonMapper.toJsonString(
                     path.extract(
                             JSONReader.of(str3)
                     )
@@ -872,7 +872,7 @@ public class JSONBTest4 {
         );
 
         assertEquals(expected,
-                JSON.toJSONString(
+                JsonMapper.toJsonString(
                     path.extract(
                             JSONReader.ofJSONB(
                                     JSONB.fromJSONBytes(
@@ -885,9 +885,9 @@ public class JSONBTest4 {
 
         assertEquals(
                 expected
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         path.eval(
-                                JSON.parseObject(str3)
+                                JsonMapper.parseJsonObject(str3)
                         )
                 )
         );
@@ -917,7 +917,7 @@ public class JSONBTest4 {
         assertEquals(expected
                 , path
                         .eval(
-                                JSON.parseObject(str3))
+                                JsonMapper.parseJsonObject(str3))
                         .toString());
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONObjectTest.java b/core/src/test/java/com/alibaba/fastjson2/JSONObjectTest.java
index 8f6777f00..a4ca05700 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONObjectTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONObjectTest.java
@@ -53,7 +53,7 @@ public class JSONObjectTest {
         object.put("obj", Collections.emptyMap());
         Integer1 obj = object.getObject("obj", Integer1.class);
         assertNotNull(obj);
-        assertEquals("{}", JSON.toJSONString(obj));
+        assertEquals("{}", JsonMapper.toJsonString(obj));
     }
 
     @Test
@@ -65,7 +65,7 @@ public class JSONObjectTest {
             }.getType());
         assertNotNull(list);
         assertEquals(Integer1.class, list.get(0).getClass());
-        assertEquals("[{}]", JSON.toJSONString(list));
+        assertEquals("[{}]", JsonMapper.toJsonString(list));
     }
 
     @Test
@@ -77,7 +77,7 @@ public class JSONObjectTest {
             }.getType());
         assertNotNull(map);
         assertEquals(Integer1.class, map.get("val").getClass());
-        assertEquals("{\"val\":{}}", JSON.toJSONString(map));
+        assertEquals("{\"val\":{}}", JsonMapper.toJsonString(map));
     }
 
     @Test
@@ -968,7 +968,7 @@ public class JSONObjectTest {
     @Test
     public void read() {
         String str = "{\"id\":123}";
-        JSONObject jsonObject = JSON.parseObject(str);
+        JSONObject jsonObject = JsonMapper.parseJsonObject(str);
         assertEquals(123, jsonObject.getIntValue("id"));
         assertEquals(123L, jsonObject.getLongValue("id"));
         assertEquals("123", jsonObject.getString("id"));
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONPathExtractTest.java b/core/src/test/java/com/alibaba/fastjson2/JSONPathExtractTest.java
index 5c5298e70..6b2843a9d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONPathExtractTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONPathExtractTest.java
@@ -151,7 +151,7 @@ public class JSONPathExtractTest {
                         .extract(
                                 JSONReader.of(json)));
         assertEquals("[]"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath
                                 .of("$[5]")
                                 .extract(
@@ -159,7 +159,7 @@ public class JSONPathExtractTest {
                 )
         );
         assertEquals("{}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath
                                 .of("$[6]")
                                 .extract(
@@ -172,7 +172,7 @@ public class JSONPathExtractTest {
     public void test_extract_all() {
         String json = "{\"v0\":0,\"v1\":\"1\",\"v2\":true,\"v3\":false,\"v4\":null}";
         assertEquals("[0,\"1\",true,false,null]"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath
                                 .of("$.*")
                                 .extract(
@@ -185,7 +185,7 @@ public class JSONPathExtractTest {
     public void test_extract_all_2() {
         String json = "{\"obj\":{\"v0\":0,\"v1\":\"1\",\"v2\":true,\"v3\":false,\"v4\":null}}";
         assertEquals("[0]"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath
                                 .of("$..v0")
                                 .extract(
@@ -193,7 +193,7 @@ public class JSONPathExtractTest {
                 )
         );
         assertEquals("[\"1\"]"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath
                                 .of("$..v1")
                                 .extract(
@@ -201,7 +201,7 @@ public class JSONPathExtractTest {
                 )
         );
         assertEquals("[true]"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath
                                 .of("$..v2")
                                 .extract(
@@ -209,7 +209,7 @@ public class JSONPathExtractTest {
                 )
         );
         assertEquals("[false]"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath
                                 .of("$..v3")
                                 .extract(
@@ -217,7 +217,7 @@ public class JSONPathExtractTest {
                 )
         );
         assertEquals("[null]"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath
                                 .of("$..v4")
                                 .extract(
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONTest.java b/core/src/test/java/com/alibaba/fastjson2/JSONTest.java
index 32ab096bf..5a57e5305 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONTest.java
@@ -22,21 +22,21 @@ import static junit.framework.TestCase.*;
 public class JSONTest {
     @Test
     public void test_parseObject_0() {
-        IntField1 vo = JSON.parseObject("{\"v0000\":101}"
+        IntField1 vo = JsonMapper.parseJsonObject("{\"v0000\":101}"
                 , (Type) IntField1.class, JSONReader.Feature.SupportSmartMatch);
         assertEquals(101, vo.v0000);
     }
 
     @Test
     public void test_isValidArray_0() {
-        assertTrue(JSON.isValidArray("[]"));
-        assertFalse(JSON.isValidArray("{}"));
+        assertTrue(JsonMapper.isValidArray("[]"));
+        assertFalse(JsonMapper.isValidArray("{}"));
     }
 
     @Test
     public void test_parseArray_0() {
         String str = "[1,2,3]";
-        List<Object> array = JSON.parseArray(str, new Type[]{int.class, long.class, String.class});
+        List<Object> array = JsonMapper.parseJsonArray(str, new Type[]{int.class, long.class, String.class});
         assertEquals(1, array.get(0));
         assertEquals(2L, array.get(1));
         assertEquals("3", array.get(2));
@@ -44,56 +44,56 @@ public class JSONTest {
 
     @Test
     public void test_parseObject_2() {
-        IntField1 vo = JSON.parseObject("{\"v0000\":101}".getBytes(StandardCharsets.UTF_8)
+        IntField1 vo = JsonMapper.parseJsonObject("{\"v0000\":101}".getBytes(StandardCharsets.UTF_8)
                 , (Type) IntField1.class);
         assertEquals(101, vo.v0000);
     }
 
     @Test
     public void test_parseObject_1() {
-        IntField1 vo = JSON.parseObject("{\"v0000\":101}".getBytes(StandardCharsets.UTF_8)
+        IntField1 vo = JsonMapper.parseJsonObject("{\"v0000\":101}".getBytes(StandardCharsets.UTF_8)
                 , (Type) IntField1.class, JSONReader.Feature.SupportSmartMatch);
         assertEquals(101, vo.v0000);
     }
 
     @Test
     public void test_parseObject_3() {
-        IntField1 vo = JSON.toJavaObject(JSON.parseObject("{\"v0000\":101}"), IntField1.class);
+        IntField1 vo = JsonMapper.convertToJavaObject(JsonMapper.parseJsonObject("{\"v0000\":101}"), IntField1.class);
         assertEquals(101, vo.v0000);
     }
 
     @Test
     public void test_parseObject_4() {
-        IntField1 vo = JSON.toJavaObject("{\"v0000\":101}", IntField1.class);
+        IntField1 vo = JsonMapper.convertToJavaObject("{\"v0000\":101}", IntField1.class);
         assertEquals(101, vo.v0000);
     }
 
     @Test
     public void test_toJSONBytes_0() {
-        assertEquals("null", new String(JSON.toJSONBytes(null, new Filter[0])));
+        assertEquals("null", new String(JsonMapper.toJsonBytes(null, new Filter[0])));
 
         ByteArrayOutputStream out = new ByteArrayOutputStream();
-        JSON.writeTo(out, null);
+        JsonMapper.writeToOutputStream(out, null);
         assertEquals("null", new String(out.toByteArray()));
     }
 
     @Test
     public void test_toJSONBytes_1() {
         assertEquals("\"test\"",
-                new String(JSON.toJSONBytes("test", new Filter[0], JSONWriter.Feature.WriteNulls)));
+                new String(JsonMapper.toJsonBytes("test", new Filter[0], JSONWriter.Feature.WriteNulls)));
         assertEquals("\"test\"",
-                new String(JSON.toJSONBytes("test", Arrays.asList(new SimplePropertyPreFilter()).toArray(new Filter[0]), JSONWriter.Feature.WriteNulls)));
+                new String(JsonMapper.toJsonBytes("test", Arrays.asList(new SimplePropertyPreFilter()).toArray(new Filter[0]), JSONWriter.Feature.WriteNulls)));
     }
 
     @Test
     public void test_object_empty() {
-        Map object = (Map) JSON.parse("{}");
+        Map object = (Map) JsonMapper.parseJson("{}");
         assertTrue(object.isEmpty());
     }
 
     @Test
     public void test_object_one() {
-        Map object = (Map) JSON.parse("{\"id\":123}");
+        Map object = (Map) JsonMapper.parseJson("{\"id\":123}");
         assertEquals(1, object.size());
         assertEquals(123, object.get("id"));
     }
@@ -107,20 +107,20 @@ public class JSONTest {
                 Serializable.class
         };
         for (Type type : types) {
-            Map object = JSON.parseObject("{}", type);
+            Map object = JsonMapper.parseJsonObject("{}", type);
             assertTrue(object.isEmpty());
         }
     }
 
     @Test
     public void test_parse_object_empty() {
-        Map object = JSON.parseObject("{}");
+        Map object = JsonMapper.parseJsonObject("{}");
         assertTrue(object.isEmpty());
     }
 
     @Test
     public void test_parse_object_one() {
-        Map object = JSON.parseObject("{\"id\":123}");
+        Map object = JsonMapper.parseJsonObject("{\"id\":123}");
         assertEquals(1, object.size());
         assertEquals(123, object.get("id"));
     }
@@ -142,7 +142,7 @@ public class JSONTest {
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{String.class, String.class}, null, type);
 
-            Map object = JSON.parseObject("{\"id\":123}", parameterizedType);
+            Map object = JsonMapper.parseJsonObject("{\"id\":123}", parameterizedType);
             assertEquals(1, object.size());
             assertEquals("123", object.get("id"));
         }
@@ -165,7 +165,7 @@ public class JSONTest {
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{String.class, Long.class}, null, type);
 
-            Map object = JSON.parseObject("{\"id\":123}", parameterizedType);
+            Map object = JsonMapper.parseJsonObject("{\"id\":123}", parameterizedType);
             assertEquals(1, object.size());
             assertEquals(123L, object.get("id"));
         }
@@ -185,7 +185,7 @@ public class JSONTest {
         };
 
         for (Type type : types) {
-            List list = (List) JSON.parseObject("[123]", type);
+            List list = (List) JsonMapper.parseJsonObject("[123]", type);
             assertEquals(1, list.size());
             assertEquals(123, list.get(0));
         }
@@ -206,7 +206,7 @@ public class JSONTest {
 
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{}, null, type);
-            List list = JSON.parseObject("[123]", parameterizedType);
+            List list = JsonMapper.parseJsonObject("[123]", parameterizedType);
             assertEquals(1, list.size());
             assertEquals(123, list.stream().findFirst().get());
         }
@@ -226,7 +226,7 @@ public class JSONTest {
 
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{String.class}, null, type);
-            List list = JSON.parseObject("[123]", parameterizedType);
+            List list = JsonMapper.parseJsonObject("[123]", parameterizedType);
             assertEquals(1, list.size());
             assertEquals("123", list.stream().findFirst().get());
         }
@@ -246,7 +246,7 @@ public class JSONTest {
 
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{Long.class}, null, type);
-            List list = JSON.parseObject("[123]", parameterizedType);
+            List list = JsonMapper.parseJsonObject("[123]", parameterizedType);
             assertEquals(1, list.size());
             assertEquals(123L, list.stream().findFirst().get());
         }
@@ -264,7 +264,7 @@ public class JSONTest {
         };
 
         for (Type type : types) {
-            Collection list = (Collection) JSON.parseObject("[123]", type);
+            Collection list = (Collection) JsonMapper.parseJsonObject("[123]", type);
             assertEquals(1, list.size());
             assertEquals(123, list.stream().findFirst().get());
         }
@@ -283,7 +283,7 @@ public class JSONTest {
 
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{String.class}, null, type);
-            Collection list = JSON.parseObject("[123]", parameterizedType);
+            Collection list = JsonMapper.parseJsonObject("[123]", parameterizedType);
             assertEquals(1, list.size());
             assertEquals("123", list.stream().findFirst().get());
         }
@@ -302,7 +302,7 @@ public class JSONTest {
 
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{Long.class}, null, type);
-            Collection list = JSON.parseObject("[123]", parameterizedType);
+            Collection list = JsonMapper.parseJsonObject("[123]", parameterizedType);
             assertEquals(1, list.size());
             assertEquals(123L, list.stream().findFirst().get());
         }
@@ -321,7 +321,7 @@ public class JSONTest {
         };
 
         for (Type type : types) {
-            Set list = (Set) JSON.parseObject("[123]", type);
+            Set list = (Set) JsonMapper.parseJsonObject("[123]", type);
             assertEquals(1, list.size());
             assertEquals(123, list.stream().findFirst().get());
         }
@@ -341,7 +341,7 @@ public class JSONTest {
 
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{String.class}, null, type);
-            Set list = (Set) JSON.parseObject("[123]", parameterizedType);
+            Set list = (Set) JsonMapper.parseJsonObject("[123]", parameterizedType);
             assertEquals(1, list.size());
             assertEquals("123", list.stream().findFirst().get());
         }
@@ -361,7 +361,7 @@ public class JSONTest {
 
         for (Type type : types) {
             ParameterizedTypeImpl parameterizedType = new ParameterizedTypeImpl(new Type[]{Long.class}, null, type);
-            Set list = (Set) JSON.parseObject("[123]", parameterizedType);
+            Set list = (Set) JsonMapper.parseJsonObject("[123]", parameterizedType);
             assertEquals(1, list.size());
             assertEquals(123L, list.stream().findFirst().get());
         }
@@ -369,58 +369,58 @@ public class JSONTest {
 
     @Test
     public void test_array_empty() {
-        List list = (List) JSON.parse("[]");
+        List list = (List) JsonMapper.parseJson("[]");
         assertTrue(list.isEmpty());
     }
 
     @Test
     public void test_array_one() {
-        List list = (List) JSON.parse("[123]");
+        List list = (List) JsonMapper.parseJson("[123]");
         assertEquals(1, list.size());
         assertEquals(123, list.get(0));
     }
 
     @Test
     public void test_parse_array_empty() {
-        List list = JSON.parseArray("[]");
+        List list = JsonMapper.parseJsonArray("[]");
         assertTrue(list.isEmpty());
     }
 
     @Test
     public void test_parse_array_one() {
-        List list = JSON.parseArray("[123]");
+        List list = JsonMapper.parseJsonArray("[123]");
         assertEquals(1, list.size());
         assertEquals(123, list.get(0));
     }
 
     @Test
     public void test_parse_array_typed() {
-        List<String> list = JSON.parseArray("[123]", String.class);
+        List<String> list = JsonMapper.parseJsonArray("[123]", String.class);
         assertEquals(1, list.size());
         assertEquals("123", list.get(0));
     }
 
     @Test
     public void test_null() {
-        assertNull(JSON.parse("null"));
+        assertNull(JsonMapper.parseJson("null"));
     }
 
     @Test
     public void test_writeNull() {
         assertEquals("null"
-                , JSON.toJSONString(null, JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(null, JSONWriter.Feature.WriteNulls));
     }
 
     @Test
     public void test_writeNull_utf8() {
         assertEquals("null"
-                , new String(JSON.toJSONBytes(null, JSONWriter.Feature.WriteNulls)));
+                , new String(JsonMapper.toJsonBytes(null, JSONWriter.Feature.WriteNulls)));
     }
 
     @Test
     public void test_writeTo_0() {
         ByteArrayOutputStream out = new ByteArrayOutputStream();
-        JSON.writeTo(out, Collections.singleton(1));
+        JsonMapper.writeToOutputStream(out, Collections.singleton(1));
         assertEquals("[1]"
                 , new String(out.toByteArray()));
     }
@@ -428,7 +428,7 @@ public class JSONTest {
     @Test
     public void test_writeTo_1() {
         ByteArrayOutputStream out = new ByteArrayOutputStream();
-        JSON.writeTo(out,
+        JsonMapper.writeToOutputStream(out,
                 null, new Filter[0], JSONWriter.Feature.WriteNulls);
         assertEquals("null"
                 , new String(out.toByteArray()));
@@ -437,7 +437,7 @@ public class JSONTest {
     @Test
     public void test_writeTo_2() {
         ByteArrayOutputStream out = new ByteArrayOutputStream();
-        JSON.writeTo(out,
+        JsonMapper.writeToOutputStream(out,
                 Collections.singleton(1), new Filter[0], JSONWriter.Feature.WriteNulls);
         assertEquals("[1]"
                 , new String(out.toByteArray()));
@@ -446,7 +446,7 @@ public class JSONTest {
     @Test
     public void test_writeTo_3() {
         ByteArrayOutputStream out = new ByteArrayOutputStream();
-        JSON.writeTo(out,
+        JsonMapper.writeToOutputStream(out,
                 Collections.singleton(1), Arrays.asList(new SimplePropertyPreFilter()).toArray(new Filter[0]), JSONWriter.Feature.WriteNulls);
         assertEquals("[1]"
                 , new String(out.toByteArray()));
@@ -454,23 +454,23 @@ public class JSONTest {
 
     @Test
     public void test_true() {
-        assertTrue((Boolean) JSON.parse("true"));
+        assertTrue((Boolean) JsonMapper.parseJson("true"));
     }
 
     @Test
     public void test_false() {
-        assertFalse((Boolean) JSON.parse("false"));
+        assertFalse((Boolean) JsonMapper.parseJson("false"));
     }
 
     @Test
     public void test_str() {
         String str = "wenshao";
-        assertEquals(str, JSON.parse("\"" + str + "\""));
+        assertEquals(str, JsonMapper.parseJson("\"" + str + "\""));
     }
 
     @Test
     public void test_num_1() {
-        assertEquals(0, JSON.parse("0"));
+        assertEquals(0, JsonMapper.parseJson("0"));
     }
 
     @Test
@@ -489,7 +489,7 @@ public class JSONTest {
                 , 1000000000
         };
         for (int i : numbers) {
-            assertEquals(i, JSON.parse(Integer.toString(i)));
+            assertEquals(i, JsonMapper.parseJson(Integer.toString(i)));
         }
     }
 
@@ -507,7 +507,7 @@ public class JSONTest {
                 , 1000000000000000000L
         };
         for (long i : numbers) {
-            assertEquals(i, JSON.parse(Long.toString(i)));
+            assertEquals(i, JsonMapper.parseJson(Long.toString(i)));
         }
     }
 
@@ -518,22 +518,22 @@ public class JSONTest {
         assertEquals(Fnv.hashCode64("@type"), ObjectReaderImplList.INSTANCE.getTypeKeyHash());
 
         assertEquals(123
-                , ((List) JSON.parseObject("\"123\""
+                , ((List) JsonMapper.parseJsonObject("\"123\""
                         , new TypeReference<List<Integer>>() {
                         }.getType()))
                         .get(0));
         assertEquals(123
-                , ((List) JSON.parseObject("\"123\""
+                , ((List) JsonMapper.parseJsonObject("\"123\""
                         , new TypeReference<LinkedList<Integer>>() {
                         }.getType()))
                         .get(0));
         assertEquals(123
-                , ((List) JSON.parseObject("\"123\""
+                , ((List) JsonMapper.parseJsonObject("\"123\""
                         , new TypeReference<ArrayList<Integer>>() {
                         }.getType()))
                         .get(0));
         assertEquals(123
-                , ((List) JSON.parseObject("\"123\""
+                , ((List) JsonMapper.parseJsonObject("\"123\""
                         , new TypeReference<AbstractList<Integer>>() {
                         }.getType()))
                         .get(0));
@@ -549,22 +549,22 @@ public class JSONTest {
 
 
         assertEquals("123"
-                , ((List) JSON.parseObject("[\"123\"]"
+                , ((List) JsonMapper.parseJsonObject("[\"123\"]"
                         , new TypeReference<List<String>>() {
                         }.getType()))
                         .get(0));
         assertEquals("123"
-                , ((List) JSON.parseObject("[\"123\"]"
+                , ((List) JsonMapper.parseJsonObject("[\"123\"]"
                         , new TypeReference<LinkedList<String>>() {
                         }.getType()))
                         .get(0));
         assertEquals("123"
-                , ((List) JSON.parseObject("[\"123\"]"
+                , ((List) JsonMapper.parseJsonObject("[\"123\"]"
                         , new TypeReference<ArrayList<String>>() {
                         }.getType()))
                         .get(0));
         assertEquals("123"
-                , ((List) JSON.parseObject("[\"123\"]"
+                , ((List) JsonMapper.parseJsonObject("[\"123\"]"
                         , new TypeReference<AbstractList<String>>() {
                         }.getType()))
                         .get(0));
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONTest_register.java b/core/src/test/java/com/alibaba/fastjson2/JSONTest_register.java
index 173df84ea..2e128028d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONTest_register.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONTest_register.java
@@ -11,14 +11,14 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class JSONTest_register {
     @Test
     public void test_register() {
-        JSON.register(VO.class, new VOWriter());
-        JSON.register(VO.class, new VOReader());
+        JsonMapper.registerObjectReader(VO.class, new VOWriter());
+        JsonMapper.registerObjectReader(VO.class, new VOReader());
 
         VO vo = new VO(123, "DataWorks");
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"ID\":123,\"NAME\":\"DataWorks\"}", str);
 
-        VO vo1 = JSON.parseObject(str, VO.class);
+        VO vo1 = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(vo.id, vo1.id);
         assertEquals(vo.name, vo1.name);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/JSONValidatorTest.java b/core/src/test/java/com/alibaba/fastjson2/JSONValidatorTest.java
index 69d05702f..d679fd05f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/JSONValidatorTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/JSONValidatorTest.java
@@ -9,10 +9,10 @@ import static org.junit.Assert.assertFalse;
 public class JSONValidatorTest {
     @Test
     public void validate_test_quotation() {
-        assertFalse(JSON.isValid("{noQuotationMarksError}"));
+        assertFalse(JsonMapper.isValid("{noQuotationMarksError}"));
         byte[] utf8 = "{noQuotationMarksError}".getBytes(StandardCharsets.UTF_8);
-        assertFalse(JSON.isValid(utf8));
-        assertFalse(JSON.isValid(utf8, 0, utf8.length, StandardCharsets.UTF_8));
-        assertFalse(JSON.isValid(utf8, 0, utf8.length, StandardCharsets.US_ASCII));
+        assertFalse(JsonMapper.isValid(utf8));
+        assertFalse(JsonMapper.isValid(utf8, 0, utf8.length, StandardCharsets.UTF_8));
+        assertFalse(JsonMapper.isValid(utf8, 0, utf8.length, StandardCharsets.US_ASCII));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/TypeReferenceTest.java b/core/src/test/java/com/alibaba/fastjson2/TypeReferenceTest.java
index 5da799b63..f593d4c15 100644
--- a/core/src/test/java/com/alibaba/fastjson2/TypeReferenceTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/TypeReferenceTest.java
@@ -18,7 +18,7 @@ public class TypeReferenceTest {
         User user = new TypeReference<User>() {
         }.parseObject(text);
 
-        assertEquals(text, JSON.toJSONString(user));
+        assertEquals(text, JsonMapper.toJsonString(user));
     }
 
     @Test
@@ -28,7 +28,7 @@ public class TypeReferenceTest {
         List<User> users = new TypeReference<User>() {
         }.parseArray(text);
 
-        assertEquals(text, JSON.toJSONString(users));
+        assertEquals(text, JsonMapper.toJsonString(users));
     }
 
     static class User {
diff --git a/core/src/test/java/com/alibaba/fastjson2/WriterFeatureTest.java b/core/src/test/java/com/alibaba/fastjson2/WriterFeatureTest.java
index c325513c7..e18b54dca 100644
--- a/core/src/test/java/com/alibaba/fastjson2/WriterFeatureTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/WriterFeatureTest.java
@@ -16,11 +16,11 @@ public class WriterFeatureTest {
         vo.setV0002(new AtomicIntegerArray(2));
 
         {
-            String str = JSON.toJSONString(vo, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
+            String str = JsonMapper.toJsonString(vo, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
             System.out.println(str);
             assertEquals("{\"v0000\":[0],\"v0001\":[],\"v0002\":[0,0]}", str);
 
-            Map<String, Object> map = JSON.parseObject(str);
+            Map<String, Object> map = JsonMapper.parseJsonObject(str);
             assertEquals(3, map.size());
             assertNotNull(map.get("v0000"));
             assertNotNull(map.get("v0001"));
@@ -28,18 +28,18 @@ public class WriterFeatureTest {
         }
 
         {
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Map<String, Object> map = JSON.parseObject(str);
+            Map<String, Object> map = JsonMapper.parseJsonObject(str);
             assertEquals(2, map.size());
             assertNotNull(map.get("v0000"));
             assertNotNull(map.get("v0002"));
         }
 
         {
-            String str = JSON.toJSONString(vo, JSONWriter.Feature.WriteNulls);
+            String str = JsonMapper.toJsonString(vo, JSONWriter.Feature.WriteNulls);
 
-            Map<String, Object> map = JSON.parseObject(str);
+            Map<String, Object> map = JsonMapper.parseJsonObject(str);
             assertEquals(3, map.size());
             assertNotNull(map.get("v0000"));
             assertNull(map.get("v0001"));
diff --git a/core/src/test/java/com/alibaba/fastjson2/annotation/BeanToArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/annotation/BeanToArrayTest.java
index bb73523a0..13380c744 100644
--- a/core/src/test/java/com/alibaba/fastjson2/annotation/BeanToArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/annotation/BeanToArrayTest.java
@@ -19,10 +19,10 @@ public class BeanToArrayTest {
         vo.id = 1001;
         vo.name = "DataWorks";
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("[1001,\"DataWorks\"]", str);
 
-        VO vo2 = JSON.parseObject(str, VO.class);
+        VO vo2 = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(vo.id, vo2.id);
         assertEquals(vo.name, vo2.name);
     }
@@ -49,7 +49,7 @@ public class BeanToArrayTest {
             assertEquals("[1001,\"DataWorks\"]", str);
         }
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         for (ObjectReaderCreator readerCreator : readerCreators) {
             ObjectReader<VO> objectReader = readerCreator.createObjectReader(VO.class);
             VO vo2 = objectReader.readObject(JSONReader.of(str));
diff --git a/core/src/test/java/com/alibaba/fastjson2/annotation/BeanToArrayTest2.java b/core/src/test/java/com/alibaba/fastjson2/annotation/BeanToArrayTest2.java
index 2e8134987..8222e2413 100644
--- a/core/src/test/java/com/alibaba/fastjson2/annotation/BeanToArrayTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/annotation/BeanToArrayTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.annotation;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.TestUtils;
@@ -22,10 +22,10 @@ public class BeanToArrayTest2 {
         vo.name = "DataWorks";
         p.value = vo;
 
-        String str = JSON.toJSONString(p);
+        String str = JsonMapper.toJsonString(p);
         assertEquals("{\"value\":[1001,\"DataWorks\"]}", str);
 
-        Parent p2 = JSON.parseObject(str, Parent.class);
+        Parent p2 = JsonMapper.parseJsonObject(str, Parent.class);
         VO vo2 = p2.value;
         assertEquals(vo.id, vo2.id);
         assertEquals(vo.name, vo2.name);
@@ -55,7 +55,7 @@ public class BeanToArrayTest2 {
             assertEquals("{\"value\":[1001,\"DataWorks\"]}", str);
         }
 
-        String str = JSON.toJSONString(p);
+        String str = JsonMapper.toJsonString(p);
         for (ObjectReaderCreator readerCreator : readerCreators) {
             ObjectReader<Parent> objectReader = readerCreator.createObjectReader(Parent.class);
             Parent p2 = objectReader.readObject(JSONReader.of(str));
diff --git a/core/src/test/java/com/alibaba/fastjson2/annotation/IgnoreErrorGetterTest.java b/core/src/test/java/com/alibaba/fastjson2/annotation/IgnoreErrorGetterTest.java
index e7842c751..f5d2430f4 100644
--- a/core/src/test/java/com/alibaba/fastjson2/annotation/IgnoreErrorGetterTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/annotation/IgnoreErrorGetterTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.annotation;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.writer.ObjectWriter;
 import com.alibaba.fastjson2.writer.ObjectWriterCreatorLambda;
@@ -16,7 +16,7 @@ public class IgnoreErrorGetterTest {
     @Test
     public void test_feature() throws Exception {
         Model model = new Model();
-        String text = JSON.toJSONString(model, JSONWriter.Feature.IgnoreErrorGetter);
+        String text = JsonMapper.toJsonString(model, JSONWriter.Feature.IgnoreErrorGetter);
         Assert.assertEquals("{}", text);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/annotation/JSONBuilderTest.java b/core/src/test/java/com/alibaba/fastjson2/annotation/JSONBuilderTest.java
index 78711ae8e..953368f9c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/annotation/JSONBuilderTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/annotation/JSONBuilderTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.annotation;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.reader.ObjectReader;
@@ -16,11 +16,11 @@ public class JSONBuilderTest {
     public void test_create() {
         String str = "{\"id\":12304,\"name\":\"ljw\"}";
         {
-            VO vo = JSON.parseObject(str, VO.class);
+            VO vo = JsonMapper.parseJsonObject(str, VO.class);
             assertEquals(12304, vo.getId());
             assertEquals("ljw", vo.getName());
         }
-        JSONObject jsonObject = JSON.parseObject(str);
+        JSONObject jsonObject = JsonMapper.parseJsonObject(str);
         {
             VO vo = jsonObject.toJavaObject(VO.class);
             assertEquals(12304, vo.getId());
@@ -40,7 +40,7 @@ public class JSONBuilderTest {
             assertEquals(12304, vo.getId());
             assertEquals("ljw", vo.getName());
         }
-        JSONObject jsonObject = JSON.parseObject(str);
+        JSONObject jsonObject = JsonMapper.parseJsonObject(str);
         {
             VO vo = objectReader.createInstance(jsonObject);
             assertEquals(12304, vo.getId());
diff --git a/core/src/test/java/com/alibaba/fastjson2/annotation/JSONCreatorTest.java b/core/src/test/java/com/alibaba/fastjson2/annotation/JSONCreatorTest.java
index 059e8e81f..f3e00d0ef 100644
--- a/core/src/test/java/com/alibaba/fastjson2/annotation/JSONCreatorTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/annotation/JSONCreatorTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.annotation;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -14,7 +14,7 @@ import static junit.framework.TestCase.assertNull;
 public class JSONCreatorTest {
     @Test
     public void test_1() {
-        VO1 vo = JSON.parseObject("{\"id8\":8,\"id16\":16,\"id32\":32,\"id64\":64}", VO1.class);
+        VO1 vo = JsonMapper.parseJsonObject("{\"id8\":8,\"id16\":16,\"id32\":32,\"id64\":64}", VO1.class);
         assertEquals(8, vo.id8);
         assertEquals(16, vo.id16);
         assertEquals(32, vo.id32);
@@ -23,7 +23,7 @@ public class JSONCreatorTest {
 
     @Test
     public void test_2() {
-        VO2 vo = JSON.parseObject("{\"id8\":8,\"id16\":16,\"id32\":32,\"id64\":64}", VO2.class);
+        VO2 vo = JsonMapper.parseJsonObject("{\"id8\":8,\"id16\":16,\"id32\":32,\"id64\":64}", VO2.class);
         assertEquals(8, vo.id8.byteValue());
         assertEquals(16, vo.id16.shortValue());
         assertEquals(32, vo.id32.intValue());
@@ -32,7 +32,7 @@ public class JSONCreatorTest {
 
     @Test
     public void test_3() {
-        VO3 vo = JSON.parseObject("{\"flag\":true,\"floatValue\":32,\"doubleValue\":64}", VO3.class);
+        VO3 vo = JsonMapper.parseJsonObject("{\"flag\":true,\"floatValue\":32,\"doubleValue\":64}", VO3.class);
         assertEquals(true, vo.flag);
         assertEquals(32F, vo.floatValue);
         assertEquals(64D, vo.doubleValue);
@@ -40,7 +40,7 @@ public class JSONCreatorTest {
 
     @Test
     public void test_4() {
-        VO4 vo = JSON.parseObject("{\"flag\":true,\"floatValue\":32,\"doubleValue\":64}", VO4.class);
+        VO4 vo = JsonMapper.parseJsonObject("{\"flag\":true,\"floatValue\":32,\"doubleValue\":64}", VO4.class);
         assertEquals(true, vo.flag.booleanValue());
         assertEquals(32F, vo.floatValue);
         assertEquals(64D, vo.doubleValue);
@@ -51,14 +51,14 @@ public class JSONCreatorTest {
         String str = "{\"flag\":true,\"decimalValue\":32,\"bigIntValue\":64,\"strVal\":\"xx\"}";
 
         {
-            VO5 vo = JSON.parseObject(str, VO5.class);
+            VO5 vo = JsonMapper.parseJsonObject(str, VO5.class);
             assertNull(vo.id);
             assertEquals(BigDecimal.valueOf(32), vo.decimalValue);
             assertEquals(BigInteger.valueOf(64), vo.bigIntValue);
             assertEquals("xx", vo.strValue);
         }
 
-        JSONObject jsonObject = JSON.parseObject(str);
+        JSONObject jsonObject = JsonMapper.parseJsonObject(str);
         VO5 vo = jsonObject.toJavaObject(VO5.class);
         assertNull(vo.id);
         assertEquals(BigDecimal.valueOf(32), vo.decimalValue);
diff --git a/core/src/test/java/com/alibaba/fastjson2/annotation/JSONFieldTest2.java b/core/src/test/java/com/alibaba/fastjson2/annotation/JSONFieldTest2.java
index 865b07bf8..a54a4d259 100644
--- a/core/src/test/java/com/alibaba/fastjson2/annotation/JSONFieldTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/annotation/JSONFieldTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.annotation;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static junit.framework.TestCase.assertEquals;
@@ -8,28 +8,28 @@ import static junit.framework.TestCase.assertEquals;
 public class JSONFieldTest2 {
     @Test
     public void test_alternateNames() {
-        VO vo = JSON.parseObject("{\"id\":101}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":101}", VO.class);
         assertEquals(101, vo.id);
 
-        VO vo2 = JSON.parseObject("{\"uid\":101}", VO.class);
+        VO vo2 = JsonMapper.parseJsonObject("{\"uid\":101}", VO.class);
         assertEquals(101, vo2.id);
     }
 
     @Test
     public void test_alternateNames_2() {
-        VO2 vo = JSON.parseObject("{\"id\":101}", VO2.class);
+        VO2 vo = JsonMapper.parseJsonObject("{\"id\":101}", VO2.class);
         assertEquals(101, vo.id);
 
-        VO2 vo2 = JSON.parseObject("{\"uid\":101}", VO2.class);
+        VO2 vo2 = JsonMapper.parseJsonObject("{\"uid\":101}", VO2.class);
         assertEquals(101, vo2.id);
     }
 
     @Test
     public void test_alternateNames_3() {
-        VO3 vo = JSON.parseObject("{\"id\":101}", VO3.class);
+        VO3 vo = JsonMapper.parseJsonObject("{\"id\":101}", VO3.class);
         assertEquals(101, vo.id);
 
-        VO3 vo2 = JSON.parseObject("{\"uid\":101}", VO3.class);
+        VO3 vo2 = JsonMapper.parseJsonObject("{\"uid\":101}", VO3.class);
         assertEquals(101, vo2.id);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/annotation/JSONFieldTest3.java b/core/src/test/java/com/alibaba/fastjson2/annotation/JSONFieldTest3.java
index 2bad0f913..91931f70b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/annotation/JSONFieldTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/annotation/JSONFieldTest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.annotation;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.JSONWriter;
@@ -46,7 +46,7 @@ public class JSONFieldTest3 {
                 JSONWriter jsonWriter = JSONWriter.ofUTF8();
                 objectWriter.write(jsonWriter, v, null, null, 0);
                 byte[] utf8Bytes = jsonWriter.getBytes();
-                assertEquals(v.value, JSON.parseObject(utf8Bytes, VO.class).value);
+                assertEquals(v.value, JsonMapper.parseJsonObject(utf8Bytes, VO.class).value);
             }
 
             for (BigDecimal value : values) {
diff --git a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicBooleanReadOnlyTest.java b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicBooleanReadOnlyTest.java
index e680f4a45..a3e61ece4 100644
--- a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicBooleanReadOnlyTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicBooleanReadOnlyTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.atomic;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.concurrent.atomic.AtomicBoolean;
@@ -13,10 +13,10 @@ public class AtomicBooleanReadOnlyTest {
     public void test_readOnly_method() {
         V0 v = new V0(true);
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":true}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(v1.getValue().get(), v.getValue().get());
     }
@@ -26,10 +26,10 @@ public class AtomicBooleanReadOnlyTest {
         V1 v = new V1();
         v.value.set(true);
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":true}", text);
 
-        V1 v1 = JSON.parseObject(text, V1.class);
+        V1 v1 = JsonMapper.parseJsonObject(text, V1.class);
 
         assertEquals(v1.value.get(), v.value.get());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicIntegerArrayFieldTest.java b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicIntegerArrayFieldTest.java
index 1274b8a87..f8c670f2c 100755
--- a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicIntegerArrayFieldTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicIntegerArrayFieldTest.java
@@ -1,12 +1,8 @@
 package com.alibaba.fastjson2.atomic;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.serializer.SerializeConfig;
-import com.alibaba.fastjson.serializer.SerializerFeature;
-import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
-import org.junit.Assert;
 import org.junit.jupiter.api.Test;
 
 import java.util.concurrent.atomic.AtomicIntegerArray;
@@ -22,10 +18,10 @@ public class AtomicIntegerArrayFieldTest {
         SerializeConfig mapping = new SerializeConfig();
         mapping.setAsmEnable(false);
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls);
         assertEquals("{\"value\":null}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(v1.getValue(), v.getValue());
     }
@@ -37,18 +33,18 @@ public class AtomicIntegerArrayFieldTest {
         SerializeConfig mapping = new SerializeConfig();
         mapping.setAsmEnable(false);
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
         assertEquals("{\"value\":[]}", text);
     }
 
     @Test
     public void test_codec_null_2() {
-        V0 v = JSON.parseObject("{\"value\":[1,2]}", V0.class);
+        V0 v = JsonMapper.parseJsonObject("{\"value\":[1,2]}", V0.class);
 
         SerializeConfig mapping = new SerializeConfig();
         mapping.setAsmEnable(false);
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
         assertEquals("{\"value\":[1,2]}", text);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicIntegerReadOnlyTest.java b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicIntegerReadOnlyTest.java
index 1f0c6ade4..8b9eba285 100644
--- a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicIntegerReadOnlyTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicIntegerReadOnlyTest.java
@@ -1,8 +1,6 @@
 package com.alibaba.fastjson2.atomic;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
-import org.junit.Assert;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.concurrent.atomic.AtomicInteger;
@@ -16,10 +14,10 @@ public class AtomicIntegerReadOnlyTest {
     public void test_readOnly_method() {
         V0 v = new V0(123);
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":123}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(v1.getValue().intValue(), v.getValue().intValue());
     }
@@ -29,10 +27,10 @@ public class AtomicIntegerReadOnlyTest {
         V1 v = new V1();
         v.value.set(123);
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":123}", text);
 
-        V1 v1 = JSON.parseObject(text, V1.class);
+        V1 v1 = JsonMapper.parseJsonObject(text, V1.class);
 
         assertEquals(v1.value.intValue(), v.value.intValue());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicLongArrayFieldTest.java b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicLongArrayFieldTest.java
index e9de87207..46b516077 100755
--- a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicLongArrayFieldTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicLongArrayFieldTest.java
@@ -1,9 +1,7 @@
 package com.alibaba.fastjson2.atomic;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
-import org.junit.Assert;
 import org.junit.jupiter.api.Test;
 
 import java.util.concurrent.atomic.AtomicLongArray;
@@ -17,10 +15,10 @@ public class AtomicLongArrayFieldTest {
         V0 v = new V0();
 
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls);
         assertEquals("{\"value\":null}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(v1.getValue(), v.getValue());
     }
@@ -29,15 +27,15 @@ public class AtomicLongArrayFieldTest {
     public void test_codec_null_1() {
         V0 v = new V0();
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
         assertEquals("{\"value\":[]}", text);
     }
 
     @Test
     public void test_codec_null_2() {
-        V0 v = JSON.parseObject("{\"value\":[1,2]}", V0.class);
+        V0 v = JsonMapper.parseJsonObject("{\"value\":[1,2]}", V0.class);
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue);
         assertEquals("{\"value\":[1,2]}", text);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicLongReadOnlyTest.java b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicLongReadOnlyTest.java
index 13eab8041..339d893a6 100644
--- a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicLongReadOnlyTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicLongReadOnlyTest.java
@@ -1,8 +1,6 @@
 package com.alibaba.fastjson2.atomic;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
-import org.junit.Assert;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.concurrent.atomic.AtomicLong;
@@ -15,10 +13,10 @@ public class AtomicLongReadOnlyTest {
     public void test_readOnly_method() {
         V0 v = new V0(123);
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":123}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(v1.getValue().intValue(), v.getValue().intValue());
     }
@@ -28,10 +26,10 @@ public class AtomicLongReadOnlyTest {
         V1 v = new V1();
         v.value.set(123);
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":123}", text);
 
-        V1 v1 = JSON.parseObject(text, V1.class);
+        V1 v1 = JsonMapper.parseJsonObject(text, V1.class);
 
         assertEquals(v1.value.intValue(), v.value.intValue());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicReferenceReadOnlyTest.java b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicReferenceReadOnlyTest.java
index b49712f06..368e2d0bc 100644
--- a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicReferenceReadOnlyTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicReferenceReadOnlyTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.atomic;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.concurrent.atomic.AtomicInteger;
@@ -14,10 +14,10 @@ public class AtomicReferenceReadOnlyTest {
     public void test_readOnly_method() {
         V0 v = new V0(new Value(123));
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":{\"id\":123}}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(v1.getValue().get().id, v.getValue().get().id);
     }
@@ -27,10 +27,10 @@ public class AtomicReferenceReadOnlyTest {
         V1 v = new V1();
         v.value.set(new Value(123));
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":{\"id\":123}}", text);
 
-        V1 v1 = JSON.parseObject(text, V1.class);
+        V1 v1 = JsonMapper.parseJsonObject(text, V1.class);
 
         assertEquals(v1.value.get().id, v.value.get().id);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicReferenceTest.java b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicReferenceTest.java
index 1ec406baa..ac17548ba 100644
--- a/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicReferenceTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/atomic/AtomicReferenceTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.atomic;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -14,10 +14,10 @@ public class AtomicReferenceTest {
     public void test_method() {
         V0 v = new V0(new Value(123));
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":{\"id\":123}}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(v1.getValue().get().id, v.getValue().get().id);
     }
@@ -39,10 +39,10 @@ public class AtomicReferenceTest {
         v.value = new AtomicReference<>();
         v.value.set(new Value(123));
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
         assertEquals("{\"value\":{\"id\":123}}", text);
 
-        V1 v1 = JSON.parseObject(text, V1.class);
+        V1 v1 = JsonMapper.parseJsonObject(text, V1.class);
 
         assertEquals(v1.value.get().id, v.value.get().id);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest0.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest0.java
index 968c76fe1..41e170667 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest0.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest0.java
@@ -3,7 +3,6 @@ package com.alibaba.fastjson2.autoType;
 
 import com.alibaba.fastjson2.*;
 import com.alibaba.fastjson2.reader.*;
-import com.alibaba.fastjson2.util.JSONBDump;
 import com.alibaba.fastjson2.writer.ObjectWriter;
 import com.alibaba.fastjson2.writer.ObjectWriterCreator;
 import com.alibaba.fastjson2.writer.ObjectWriterCreatorASM;
@@ -19,11 +18,11 @@ public class AutoTypeTest0 {
     @Test
     public void test_0() throws Exception {
         String text = "{\"@type\":\"com.alibaba.fastjson2_vo.IntField1\",\"v0000\":123}";
-        IntField1 model = (IntField1) JSON.parseObject(text, Object.class, JSONReader.Feature.SupportAutoType);
+        IntField1 model = (IntField1) JsonMapper.parseJsonObject(text, Object.class, JSONReader.Feature.SupportAutoType);
         assertEquals(123, model.v0000);
 
-        assertTrue(JSON.parse(text) instanceof java.util.Map);
-        IntField1 model2 = (IntField1) JSON.parse(text, JSONReader.Feature.SupportAutoType);
+        assertTrue(JsonMapper.parseJson(text) instanceof java.util.Map);
+        IntField1 model2 = (IntField1) JsonMapper.parseJson(text, JSONReader.Feature.SupportAutoType);
         assertEquals(123, model2.v0000);
     }
 
@@ -143,10 +142,10 @@ public class AutoTypeTest0 {
         IntField1 m = new IntField1();
         m.v0000 = 123;
 
-        String text = JSON.toJSONString(m, JSONWriter.Feature.WriteClassName);
+        String text = JsonMapper.toJsonString(m, JSONWriter.Feature.WriteClassName);
 
         assertEquals(text, "{\"@type\":\"com.alibaba.fastjson2_vo.IntField1\",\"v0000\":123}");
-        IntField1 model = (IntField1) JSON.parseObject(text, Object.class, JSONReader.Feature.SupportAutoType);
+        IntField1 model = (IntField1) JsonMapper.parseJsonObject(text, Object.class, JSONReader.Feature.SupportAutoType);
         assertEquals(m.v0000, model.v0000);
     }
 
@@ -155,7 +154,7 @@ public class AutoTypeTest0 {
         IntField1 m = new IntField1();
         m.v0000 = 123;
 
-        String text = JSON.toJSONString(m, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.NotWriteRootClassName);
+        String text = JsonMapper.toJsonString(m, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.NotWriteRootClassName);
 
         assertEquals(text, "{\"v0000\":123}");
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest1.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest1.java
index 02f01891b..336b9f76f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest1.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest1.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -18,10 +18,10 @@ public class AutoTypeTest1 {
         a.list.add(new C(1001));
         a.list.add(new C(1002));
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"list\":[{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest1$C\",\"id\":1001},{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest1$C\",\"id\":1002}]}", json);
 
-        A a2 = JSON.parseObject(json, A.class, JSONReader.Feature.SupportAutoType);
+        A a2 = JsonMapper.parseJsonObject(json, A.class, JSONReader.Feature.SupportAutoType);
         assertSame(a2.list.get(0).getClass(), C.class);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest10.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest10.java
index 72dc2a403..dea6efceb 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest10.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest10.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -26,7 +26,7 @@ public class AutoTypeTest10 {
         bean.values = list;
 
         byte[] bytes = JSONB.toBytes(bean, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         Bean bean2 = (Bean) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);;
         List list2 = bean2.values;
@@ -48,7 +48,7 @@ public class AutoTypeTest10 {
         bean.values = list;
 
         byte[] bytes = JSONB.toBytes(bean, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased, JSONWriter.Feature.ReferenceDetection);
-        System.out.println(JSON.toJSONString(
+        System.out.println(JsonMapper.toJsonString(
                 JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         Bean bean2 = (Bean) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);;
@@ -66,7 +66,7 @@ public class AutoTypeTest10 {
         object.put("data", list);
 
         byte[] bytes = JSONB.toBytes(object, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         com.alibaba.fastjson.JSONObject object2 = (com.alibaba.fastjson.JSONObject) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);;
         ArrayList list2 = (ArrayList) object2.get("data");
@@ -81,7 +81,7 @@ public class AutoTypeTest10 {
         object.put("data", list);
 
         byte[] bytes = JSONB.toBytes(object, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         com.alibaba.fastjson.JSONObject object2 = (com.alibaba.fastjson.JSONObject) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);;
         ArrayList list2 = (ArrayList) object2.get("data");
@@ -99,7 +99,7 @@ public class AutoTypeTest10 {
         array[1] = new com.alibaba.fastjson.JSONObject(true);
 
         byte[] bytes = JSONB.toBytes(array, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         Object[] array2 = (Object[]) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);;
         assertEquals(array[0].getClass(), array2[0].getClass());
@@ -116,7 +116,7 @@ public class AutoTypeTest10 {
         bean.value = 1L;
 
         byte[] bytes = JSONB.toBytes(bean, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         Bean2 bean2 = (Bean2) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);;
         assertEquals(bean.value, bean2.value);
@@ -154,7 +154,7 @@ public class AutoTypeTest10 {
         bean.params.add(new Item4());
 
         byte[] bytes = JSONB.toBytes(bean, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         Bean4 bean2 = (Bean4) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);
         assertEquals(bean.params.getClass(), bean2.params.getClass());
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest16_pairKey.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest16_pairKey.java
index 5e9fdb1c4..d71746214 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest16_pairKey.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest16_pairKey.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -50,7 +50,7 @@ public class AutoTypeTest16_pairKey {
     @Test
     public void test_1() throws Exception {
         String str = "{\"left\":\"key\",\"right\":101}";
-        Pair pair = JSON.parseObject(str, Pair.class);
+        Pair pair = JsonMapper.parseJsonObject(str, Pair.class);
         assertEquals("key", pair.getLeft());
         assertEquals(101, pair.getRight());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest2.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest2.java
index 1fabbcd08..1701fab32 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -18,10 +18,10 @@ public class AutoTypeTest2 {
         a.list.add(new C(1001));
         a.list.add(new C(1002));
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"list\":[{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest2$C\",\"id\":1001},{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest2$C\",\"id\":1002}]}", json);
 
-        A a2 = JSON.parseObject(json, A.class, JSONReader.Feature.SupportAutoType);
+        A a2 = JsonMapper.parseJsonObject(json, A.class, JSONReader.Feature.SupportAutoType);
         assertSame(a2.list.get(0).getClass(), C.class);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest3.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest3.java
index 05a5fb457..5a130c154 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONType;
@@ -15,10 +15,10 @@ public class AutoTypeTest3 {
         A a = new A();
         a.value = new C(1001);
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"value\":{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest3$C\",\"id\":1001}}", json);
 
-        A a2 = JSON.parseObject(json, A.class);
+        A a2 = JsonMapper.parseJsonObject(json, A.class);
         assertSame(a2.value.getClass(), C.class);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest4.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest4.java
index 1211f20fb..34d19ae24 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest4.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest4.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONType;
@@ -15,10 +15,10 @@ public class AutoTypeTest4 {
         A a = new A();
         a.value = new C(1001);
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"value\":{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest4$C\",\"id\":1001}}", json);
 
-        A a2 = JSON.parseObject(json, A.class);
+        A a2 = JsonMapper.parseJsonObject(json, A.class);
         assertSame(a2.value.getClass(), C.class);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest47.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest47.java
index 873f6a121..be157dde4 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest47.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest47.java
@@ -1,11 +1,9 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.JSONReader;
-import com.alibaba.fastjson2.reader.ObjectReaderProvider;
 import com.alibaba.fastjson2.util.TypeUtils;
-import com.alibaba.fastjson2_vo.IntField1;
 import com.mchange.v2.c3p0.impl.PoolBackedDataSourceBase;
 import org.junit.jupiter.api.Test;
 
@@ -21,7 +19,7 @@ public class AutoTypeTest47 {
                         ? TypeUtils.loadClass(typeName)
                         : null
         );
-        PoolBackedDataSourceBase dataSource = (PoolBackedDataSourceBase) JSON.parseObject(text, Object.class, JSONReader.Feature.SupportAutoType);
+        PoolBackedDataSourceBase dataSource = (PoolBackedDataSourceBase) JsonMapper.parseJsonObject(text, Object.class, JSONReader.Feature.SupportAutoType);
         assertNotNull(dataSource);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest48.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest48.java
index 9af714604..1f5160cf4 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest48.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest48.java
@@ -11,7 +11,7 @@ public class AutoTypeTest48 {
     @Test
     public void test_0() throws Exception {
         assertThrows(JSONException.class, () -> {
-                    JSON.parse((String) JSONB
+                    JsonMapper.parseJson((String) JSONB
                             .parse(Base64.getDecoder()
                             .decode("eThueyJAdHlwZSI6Iltjb20uc3VuLnJvd3NldC5KZGJjUm93U2V0SW1wbCIsWyJkYXRhU291cmNlTmFtZSI6ImxkYXA6Ly8xMjcuMC4wLjE6MTM4OS9qcnRmbnkiLCJhdXRvQ29tbWl0Ijp0cnVlXX0=")
                             ), JSONReader.Feature.SupportAutoType
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest5.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest5.java
index 77b5a7dbf..181132477 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest5.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest5.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONException;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -13,12 +13,12 @@ public class AutoTypeTest5 {
         A a = new A();
         a.value = new C(1001);
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"value\":{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest5$C\",\"id\":1001}}", json);
 
         Throwable error = null;
         try {
-            JSON.parseObject(json, A.class);
+            JsonMapper.parseJsonObject(json, A.class);
         } catch (JSONException ex) {
             error = ex;
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest6.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest6.java
index 9ed630e54..0e93adf43 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest6.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest6.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -13,10 +13,10 @@ public class AutoTypeTest6 {
         A a = new A();
         a.value = new C(1001);
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"value\":{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest6$C\",\"id\":1001}}", json);
 
-        A a2 = JSON.parseObject(json, A.class);
+        A a2 = JsonMapper.parseJsonObject(json, A.class);
         assertSame(a2.value.getClass(), B.class); // autoType not work
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest7.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest7.java
index 828ace44d..aa88d5a49 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest7.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest7.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONField;
@@ -23,10 +23,10 @@ public class AutoTypeTest7 {
         A a = new A();
         a.value = new C(1001);
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"value\":{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest7$C\",\"id\":1001}}", json);
 
-        A a2 = JSON.parseObject(json, A.class);
+        A a2 = JsonMapper.parseJsonObject(json, A.class);
         assertSame(a2.value.getClass(), C.class);
     }
 
@@ -35,10 +35,10 @@ public class AutoTypeTest7 {
         A1 a = new A1();
         a.value = new C(1001);
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"value\":{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest7$C\",\"id\":1001}}", json);
 
-        A1 a2 = JSON.parseObject(json, A1.class);
+        A1 a2 = JsonMapper.parseJsonObject(json, A1.class);
         assertSame(a2.value.getClass(), C.class);
     }
 
@@ -69,7 +69,7 @@ public class AutoTypeTest7 {
             assertEquals("{\"value\":{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest7$C\",\"id\":1001}}", json);
         }
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"value\":{\"@type\":\"com.alibaba.fastjson2.autoType.AutoTypeTest7$C\",\"id\":1001}}", json);
 
         for (ObjectReaderCreator readerCreator : readerCreators) {
diff --git a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest8.java b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest8.java
index eb02351e0..af94b985f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest8.java
+++ b/core/src/test/java/com/alibaba/fastjson2/autoType/AutoTypeTest8.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.autoType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -65,7 +65,7 @@ public class AutoTypeTest8 {
         list.add(new A());
 
         byte[] bytes = JSONB.toBytes(list, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         ArrayList list2 = (ArrayList) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);
         assertEquals(A.class, list2.get(0).getClass());
@@ -77,7 +77,7 @@ public class AutoTypeTest8 {
         list.add(new A());
 
         byte[] bytes = JSONB.toBytes(list, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         LinkedList list2 = (LinkedList) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);
         assertEquals(A.class, list2.get(0).getClass());
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/ClassTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/ClassTest.java
index 7badf1479..ea11cccfe 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/ClassTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/ClassTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static junit.framework.TestCase.assertEquals;
@@ -8,7 +8,7 @@ import static junit.framework.TestCase.assertEquals;
 public class ClassTest {
     @Test
     public void test_0() {
-        assertEquals("\"int\"", JSON.toJSONString(int.class));
-        assertEquals("\"java.lang.Integer\"", JSON.toJSONString(Integer.class));
+        assertEquals("\"int\"", JsonMapper.toJsonString(int.class));
+        assertEquals("\"java.lang.Integer\"", JsonMapper.toJsonString(Integer.class));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/ExceptionTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/ExceptionTest.java
index 73605a349..37408b70b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/ExceptionTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/ExceptionTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.util.JSONBDump;
@@ -15,14 +15,14 @@ public class ExceptionTest {
     @Test
     public void test_exception() throws Exception {
         IllegalStateException ex = new IllegalStateException();
-        String str = JSON.toJSONString(ex);
+        String str = JsonMapper.toJsonString(ex);
         System.out.println(str);
 
-        Object jsonObject = JSON.parseObject(str, Object.class);
+        Object jsonObject = JsonMapper.parseJsonObject(str, Object.class);
         assertTrue(jsonObject instanceof Map);
 
         IllegalStateException error = (IllegalStateException)
-                JSON.parseObject(str, Throwable.class);
+                JsonMapper.parseJsonObject(str, Throwable.class);
         assertNotNull(error);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/GenericTypeFieldTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/GenericTypeFieldTest.java
index ad5a0c2df..464d044b2 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/GenericTypeFieldTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/GenericTypeFieldTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.reader.ObjectReader;
 import com.alibaba.fastjson2.reader.ObjectReaderCreator;
@@ -121,7 +121,7 @@ public class GenericTypeFieldTest {
     public void testRead31_wild() throws Exception {
         Type objectType = new TypeReference<P31<? extends String>>() {}.getType();
 
-        P31 p31 = JSON.parseObject("{\"value\":101}", objectType);
+        P31 p31 = JsonMapper.parseJsonObject("{\"value\":101}", objectType);
         assertEquals("101", p31.value);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest2.java b/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest2.java
index fa68fbf2c..a78b4296d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest2.java
@@ -30,7 +30,7 @@ public class JSONBTableTest2 {
         JSONBDump.dump(bytes);
 
         A a1 = JSONB.parseObject(bytes, A.class);
-        assertEquals(JSON.toJSONString(a), JSON.toJSONString(a1));
+        assertEquals(JsonMapper.toJsonString(a), JsonMapper.toJsonString(a1));
     }
 
     @Test
@@ -47,7 +47,7 @@ public class JSONBTableTest2 {
 
         byte[] bytes = JSONB.toBytes(c);
         C c1 = JSONB.parseObject(bytes, C.class);
-        assertEquals(JSON.toJSONString(c), JSON.toJSONString(c1));
+        assertEquals(JsonMapper.toJsonString(c), JsonMapper.toJsonString(c1));
 
         assertTrue(c1.list1.get(0) instanceof Item);
         assertFalse(c1.list2.get(0) instanceof Item);
@@ -70,7 +70,7 @@ public class JSONBTableTest2 {
         JSONBDump.dump(bytes);
 
         C c1 = JSONB.parseObject(bytes, C.class, JSONReader.Feature.SupportAutoType);
-        assertEquals(JSON.toJSONString(c), JSON.toJSONString(c1));
+        assertEquals(JsonMapper.toJsonString(c), JsonMapper.toJsonString(c1));
 
         assertTrue(c1.list1.get(0) instanceof Item);
         assertTrue(c1.list2.get(0) instanceof Item);
@@ -85,7 +85,7 @@ public class JSONBTableTest2 {
 
         byte[] bytes = JSONB.toBytes(b);
         B b1 = JSONB.parseObject(bytes, B.class);
-        assertEquals(JSON.toJSONString(b), JSON.toJSONString(b1));
+        assertEquals(JsonMapper.toJsonString(b), JsonMapper.toJsonString(b1));
         assertFalse(b1.list2.get(0) instanceof Item);
     }
 
@@ -98,7 +98,7 @@ public class JSONBTableTest2 {
 
         byte[] bytes = JSONB.toBytes(b, JSONWriter.Feature.ReferenceDetection, JSONWriter.Feature.WriteClassName);
         B b1 = JSONB.parseObject(bytes, B.class, JSONReader.Feature.SupportAutoType);
-        assertEquals(JSON.toJSONString(b), JSON.toJSONString(b1));
+        assertEquals(JsonMapper.toJsonString(b), JsonMapper.toJsonString(b1));
         assertTrue(b1.list2.get(0) instanceof Item);
     }
 
@@ -111,7 +111,7 @@ public class JSONBTableTest2 {
 
         byte[] bytes = JSONB.toBytes(d);
         D d1 = JSONB.parseObject(bytes, D.class);
-        assertEquals(JSON.toJSONString(d), JSON.toJSONString(d1));
+        assertEquals(JsonMapper.toJsonString(d), JsonMapper.toJsonString(d1));
         assertFalse(d1.list2.get(0) instanceof Item);
     }
 
@@ -124,7 +124,7 @@ public class JSONBTableTest2 {
 
     public static class Item {
         public int id;
-        
+
         public static Item of(int id) {
             Item b = new Item();
             b.id = id;
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest3.java b/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest3.java
index 53820d868..1c518d16f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -26,7 +26,7 @@ public class JSONBTableTest3 {
 
         byte[] bytes = JSONB.toBytes(a);
         A a1 = JSONB.parseObject(bytes, A.class);
-        assertEquals(JSON.toJSONString(a), JSON.toJSONString(a1));
+        assertEquals(JsonMapper.toJsonString(a), JsonMapper.toJsonString(a1));
     }
 
     @Test
@@ -49,7 +49,7 @@ public class JSONBTableTest3 {
 
         byte[] bytes = JSONB.toBytes(a);
         A a1 = JSONB.parseObject(bytes, A.class);
-        assertEquals(JSON.toJSONString(a), JSON.toJSONString(a1));
+        assertEquals(JsonMapper.toJsonString(a), JsonMapper.toJsonString(a1));
     }
 
     public static class A {
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest4.java b/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest4.java
index ba536a659..d6fce8f21 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest4.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest4.java
@@ -20,7 +20,7 @@ public class JSONBTableTest4 {
 
         byte[] bytes = JSONB.toBytes(a);
         A a1 = JSONB.parseObject(bytes, A.class);
-        assertEquals(JSON.toJSONString(a), JSON.toJSONString(a1));
+        assertEquals(JsonMapper.toJsonString(a), JsonMapper.toJsonString(a1));
     }
 
     @Test
@@ -49,7 +49,7 @@ public class JSONBTableTest4 {
         System.out.println(Arrays.toString(bytes));
 
         B a1 = JSONB.parseObject(bytes, B.class, JSONReader.Feature.SupportAutoType);
-        assertEquals(JSON.toJSONString(a), JSON.toJSONString(a1));
+        assertEquals(JsonMapper.toJsonString(a), JsonMapper.toJsonString(a1));
     }
 
     @Test
@@ -102,7 +102,7 @@ public class JSONBTableTest4 {
         JSONBDump.dump(bytes);
 
         B10 a1 = JSONB.parseObject(bytes, B10.class, JSONReader.Feature.SupportAutoType);
-        assertEquals(JSON.toJSONString(a), JSON.toJSONString(a1));
+        assertEquals(JsonMapper.toJsonString(a), JsonMapper.toJsonString(a1));
     }
 
     @Test
@@ -136,7 +136,7 @@ public class JSONBTableTest4 {
         System.out.println(Arrays.toString(bytes));
 
         C a1 = JSONB.parseObject(bytes, C.class, JSONReader.Feature.SupportAutoType);
-        assertEquals(JSON.toJSONString(a), JSON.toJSONString(a1));
+        assertEquals(JsonMapper.toJsonString(a), JsonMapper.toJsonString(a1));
     }
 
     public static class A {
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest7.java b/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest7.java
index 558c2eed0..3946a2034 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest7.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/JSONBTableTest7.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -19,7 +19,7 @@ public class JSONBTableTest7 {
         list.add(new com.alibaba.fastjson.JSONObject().fluentPut("id", 102));
 
         byte[] bytes = JSONB.toBytes(list, JSONWriter.Feature.WriteClassName, JSONWriter.Feature.FieldBased);
-        System.out.println(JSON.toJSONString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
+        System.out.println(JsonMapper.toJsonString(JSONB.parse(bytes, JSONReader.Feature.SupportAutoType)));
 
         List list2 = (List) JSONB.parseObject(bytes, Object.class, JSONReader.Feature.SupportAutoType, JSONReader.Feature.FieldBased);;
         assertEquals(list2.size(), list.size());
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/LCaseTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/LCaseTest.java
index 405f6393c..4ae0d6f64 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/LCaseTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/LCaseTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import org.junit.jupiter.api.Test;
 
@@ -11,14 +11,14 @@ public class LCaseTest {
     @Test
     public void test_0() throws Exception {
         String str = "{\"optimal_height\":400}";
-        Image image = JSON.parseObject(str, Image.class);
+        Image image = JsonMapper.parseJsonObject(str, Image.class);
         assertEquals(0, image.optimalHeight);
     }
 
     @Test
     public void test_1() throws Exception {
         String str = "{\"optimal_height\":400}";
-        Image image = JSON.parseObject(str, Image.class, JSONReader.Feature.SupportSmartMatch);
+        Image image = JsonMapper.parseJsonObject(str, Image.class, JSONReader.Feature.SupportSmartMatch);
         assertEquals(400, image.optimalHeight);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/NonDefaulConstructorTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/NonDefaulConstructorTest.java
index 52a3ed763..50df1148d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/NonDefaulConstructorTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/NonDefaulConstructorTest.java
@@ -45,7 +45,7 @@ public class NonDefaulConstructorTest {
 
         Exception error = null;
         try {
-            JSON.parseObject(str, VO2.class);
+            JsonMapper.parseJsonObject(str, VO2.class);
         } catch (JSONException ex) {
             error = ex;
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/NonDefaulConstructorTestTest2.java b/core/src/test/java/com/alibaba/fastjson2/codec/NonDefaulConstructorTestTest2.java
index e6ce5ebb9..3a7412126 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/NonDefaulConstructorTestTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/NonDefaulConstructorTestTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
@@ -14,7 +14,7 @@ public class NonDefaulConstructorTestTest2 {
     @Test
     public void test_a() {
         String str = JSONObject.of("unit", 3).toString();
-        A a = JSON.parseObject(str, A.class);
+        A a = JsonMapper.parseJsonObject(str, A.class);
         assertEquals(3, a.unit);
     }
 
@@ -22,7 +22,7 @@ public class NonDefaulConstructorTestTest2 {
     public void test_b() {
         JSONObject obj = JSONObject.of("id", 3);
         String str = obj.toString();
-        assertEquals(3, JSON.parseObject(str, B.class).id);
+        assertEquals(3, JsonMapper.parseJsonObject(str, B.class).id);
 
         byte[] bytes = JSONB.toBytes(obj);
         assertEquals(3, JSONB.parseObject(bytes, B.class).id);
@@ -31,7 +31,7 @@ public class NonDefaulConstructorTestTest2 {
     @Test
     public void test_ab() {
         String str = JSONObject.of("id", 3).fluentPut("name", "DataWorks").toString();
-        B a = JSON.parseObject(str, B.class);
+        B a = JsonMapper.parseJsonObject(str, B.class);
         assertEquals(3, a.id);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/OverrideTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/OverrideTest.java
index 77ed6235f..74a11b2d9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/OverrideTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/OverrideTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.reader.ObjectReader;
 import com.alibaba.fastjson2.reader.ObjectReaderCreator;
@@ -19,7 +19,7 @@ public class OverrideTest {
         assertEquals(0, cat.id);
         assertEquals(1001, cat.catId);
 
-        String str = JSON.toJSONString(cat);
+        String str = JsonMapper.toJsonString(cat);
         assertEquals("{\"id\":1001}", str);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/ParseMapTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/ParseMapTest.java
index dec9c11c3..d38e0e871 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/ParseMapTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/ParseMapTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.*;
@@ -15,84 +15,84 @@ public class ParseMapTest {
     @Test
     public void test_ConcurrentMap() {
         String str = "{}";
-        ConcurrentMap map = JSON.parseObject(str, ConcurrentMap.class);
+        ConcurrentMap map = JsonMapper.parseJsonObject(str, ConcurrentMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_ConcurrentHashMap() {
         String str = "{}";
-        ConcurrentHashMap map = JSON.parseObject(str, ConcurrentHashMap.class);
+        ConcurrentHashMap map = JsonMapper.parseJsonObject(str, ConcurrentHashMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_ConcurrentNavigableMap() {
         String str = "{}";
-        ConcurrentNavigableMap map = JSON.parseObject(str, ConcurrentNavigableMap.class);
+        ConcurrentNavigableMap map = JsonMapper.parseJsonObject(str, ConcurrentNavigableMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_ConcurrentSkipListMap() {
         String str = "{}";
-        ConcurrentSkipListMap map = JSON.parseObject(str, ConcurrentSkipListMap.class);
+        ConcurrentSkipListMap map = JsonMapper.parseJsonObject(str, ConcurrentSkipListMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_NavigableMap() {
         String str = "{}";
-        NavigableMap map = JSON.parseObject(str, NavigableMap.class);
+        NavigableMap map = JsonMapper.parseJsonObject(str, NavigableMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_SortedMap() {
         String str = "{}";
-        SortedMap map = JSON.parseObject(str, SortedMap.class);
+        SortedMap map = JsonMapper.parseJsonObject(str, SortedMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_TreeMap() {
         String str = "{}";
-        TreeMap map = JSON.parseObject(str, TreeMap.class);
+        TreeMap map = JsonMapper.parseJsonObject(str, TreeMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_HashMap() {
         String str = "{}";
-        HashMap map = JSON.parseObject(str, HashMap.class);
+        HashMap map = JsonMapper.parseJsonObject(str, HashMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_LinkedHashMap() {
         String str = "{}";
-        LinkedHashMap map = JSON.parseObject(str, LinkedHashMap.class);
+        LinkedHashMap map = JsonMapper.parseJsonObject(str, LinkedHashMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_IdentityHashMap() {
         String str = "{}";
-        IdentityHashMap map = JSON.parseObject(str, IdentityHashMap.class);
+        IdentityHashMap map = JsonMapper.parseJsonObject(str, IdentityHashMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_AbstractMap() {
         String str = "{}";
-        AbstractMap map = JSON.parseObject(str, AbstractMap.class);
+        AbstractMap map = JsonMapper.parseJsonObject(str, AbstractMap.class);
         assertEquals(0, map.size());
     }
 
     @Test
     public void test_MyMap() {
         String str = "{}";
-        MyMap map = JSON.parseObject(str, MyMap.class);
+        MyMap map = JsonMapper.parseJsonObject(str, MyMap.class);
         assertEquals(0, map.size());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/ParseSetTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/ParseSetTest.java
index 4c7698c66..a08839629 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/ParseSetTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/ParseSetTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -13,50 +13,50 @@ import static org.junit.Assert.*;
 public class ParseSetTest {
     @Test
     public void test_Set() {
-        Set set = JSON.parseObject("[]", Set.class);
+        Set set = JsonMapper.parseJsonObject("[]", Set.class);
         assertTrue(set.isEmpty());
     }
 
     @Test
     public void test_HashSet() {
-        HashSet set = JSON.parseObject("[]", HashSet.class);
+        HashSet set = JsonMapper.parseJsonObject("[]", HashSet.class);
         assertTrue(set.isEmpty());
     }
 
     @Test
     public void test_LinkedHashSet() {
-        LinkedHashSet set = JSON.parseObject("[]", LinkedHashSet.class);
+        LinkedHashSet set = JsonMapper.parseJsonObject("[]", LinkedHashSet.class);
         assertTrue(set.isEmpty());
     }
 
     @Test
     public void test_TreeSet() {
-        TreeSet set = JSON.parseObject("[]", TreeSet.class);
+        TreeSet set = JsonMapper.parseJsonObject("[]", TreeSet.class);
         assertTrue(set.isEmpty());
     }
 
     @Test
     public void test_AbstractSet() {
-        AbstractSet set = JSON.parseObject("[]", AbstractSet.class);
+        AbstractSet set = JsonMapper.parseJsonObject("[]", AbstractSet.class);
         assertTrue(set.isEmpty());
     }
 
     @Test
     public void test_NavigableSet() {
-        NavigableSet set = JSON.parseObject("[]", NavigableSet.class);
+        NavigableSet set = JsonMapper.parseJsonObject("[]", NavigableSet.class);
         assertTrue(set.isEmpty());
     }
 
     @Test
     public void test_ConcurrentSkipListSet() {
-        ConcurrentSkipListSet set = JSON.parseObject("[]", ConcurrentSkipListSet.class);
+        ConcurrentSkipListSet set = JsonMapper.parseJsonObject("[]", ConcurrentSkipListSet.class);
         assertTrue(set.isEmpty());
     }
 
     @Test
     public void test_emptySet() {
         Class<Set> clazz = (Class<Set>) Collections.emptySet().getClass();
-        Set set = JSON.parseObject("[]", clazz);
+        Set set = JsonMapper.parseJsonObject("[]", clazz);
         assertTrue(set.isEmpty());
         assertSame(Collections.emptySet(), set);
     }
@@ -73,7 +73,7 @@ public class ParseSetTest {
     @Test
     public void test_emptyList() {
         Class clazz = Collections.emptyList().getClass();
-        List list = (List) JSON.parseObject("[]", clazz);
+        List list = (List) JsonMapper.parseJsonObject("[]", clazz);
         assertTrue(list.isEmpty());
         assertSame(Collections.emptyList(), list);
     }
@@ -90,7 +90,7 @@ public class ParseSetTest {
     @Test
     public void test_singleton() {
         Class clazz = Collections.singleton(1).getClass();
-        Collection singleton = (Collection) JSON.parseObject("[101]", clazz);
+        Collection singleton = (Collection) JsonMapper.parseJsonObject("[101]", clazz);
         assertFalse(singleton.isEmpty());
         assertEquals(1, singleton.size());
         assertEquals(101, singleton.stream().findFirst().get());
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/ReflectTypeTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/ReflectTypeTest.java
index 4e52686a8..7192b094a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/ReflectTypeTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/ReflectTypeTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONException;
 import com.alibaba.fastjson2.JSONReader;
@@ -17,7 +17,7 @@ import static junit.framework.TestCase.*;
 public class ReflectTypeTest {
     @Test
     public void test_0() throws Exception {
-        assertEquals("\"" + A.class.getName() + "\"", JSON.toJSONString(A.class));
+        assertEquals("\"" + A.class.getName() + "\"", JsonMapper.toJsonString(A.class));
 
         byte[] jsonbBytes = JSONB.toBytes(A.class);
 
@@ -35,8 +35,8 @@ public class ReflectTypeTest {
     @Test
     public void test_paramType() {
         ParameterizedTypeImpl paramType = new ParameterizedTypeImpl(new Type[]{String.class, String.class}, null, Map.class);
-        String str = JSON.toJSONString(paramType);
-        ParameterizedType paramType1 = JSON.parseObject(str, ParameterizedType.class);
+        String str = JsonMapper.toJsonString(paramType);
+        ParameterizedType paramType1 = JsonMapper.parseJsonObject(str, ParameterizedType.class);
         assertEquals(paramType, paramType1);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/SeeAlsoTest3.java b/core/src/test/java/com/alibaba/fastjson2/codec/SeeAlsoTest3.java
index 859bf14c4..c67c16ad5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/SeeAlsoTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/SeeAlsoTest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONType;
@@ -73,10 +73,10 @@ public class SeeAlsoTest3 {
     public void test_seeAlso_write() throws Exception {
         Cat cat = new Cat();
         cat.catId = 101;
-        String str = JSON.toJSONString(cat);
+        String str = JsonMapper.toJsonString(cat);
         assertEquals("{\"catId\":101}", str);
 
-        String str2 = JSON.toJSONString(cat, JSONWriter.Feature.WriteClassName);
+        String str2 = JsonMapper.toJsonString(cat, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"type\":\"Cat\",\"catId\":101}", str2);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/SkipTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/SkipTest.java
index 4d7796805..f96c29abf 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/SkipTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/SkipTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONPath;
 import com.alibaba.fastjson2.JSONReader;
 import org.junit.jupiter.api.Test;
@@ -13,15 +13,15 @@ public class SkipTest {
     @Test
     public void test_0() {
         assertEquals(0
-                , JSON.parseObject("{\"value\":123}".getBytes(StandardCharsets.UTF_8)
+                , JsonMapper.parseJsonObject("{\"value\":123}".getBytes(StandardCharsets.UTF_8)
                         , A.class).id);
 
         assertEquals(0
-                , JSON.parseObject("{\"value\":123,\"name\":\"DataWorks\"}".getBytes(StandardCharsets.UTF_8)
+                , JsonMapper.parseJsonObject("{\"value\":123,\"name\":\"DataWorks\"}".getBytes(StandardCharsets.UTF_8)
                         , A.class).id);
 
         assertEquals(0
-                , JSON.parseObject("{\"value\":123,\"name\":\"DataWorks\"}".getBytes(StandardCharsets.UTF_8)
+                , JsonMapper.parseJsonObject("{\"value\":123,\"name\":\"DataWorks\"}".getBytes(StandardCharsets.UTF_8)
                         , A1.class).id);
 
         assertEquals("DataWorks"
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/TestExternal.java b/core/src/test/java/com/alibaba/fastjson2/codec/TestExternal.java
index 971f2d387..17db7c786 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/TestExternal.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/TestExternal.java
@@ -1,10 +1,9 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.reader.ObjectReaderCreatorASM;
 import com.alibaba.fastjson2.writer.ObjectWriterCreatorASM;
-import junit.framework.TestCase;
 import org.apache.commons.io.IOUtils;
 import org.junit.jupiter.api.Test;
 
@@ -21,10 +20,10 @@ public class TestExternal {
         Method method = clazz.getMethod("setName", new Class[] {String.class});
         Object obj = clazz.newInstance();
         method.invoke(obj, "jobs");
-        
-        String text = JSON.toJSONString(obj);
+
+        String text = JsonMapper.toJsonString(obj);
         System.out.println(text);
-        JSON.parseObject(text, clazz);
+        JsonMapper.parseJsonObject(text, clazz);
     }
 
     @Test
@@ -39,24 +38,24 @@ public class TestExternal {
             Object obj = clazz.newInstance();
             method.invoke(obj, "jobs");
 
-            String text = JSON.toJSONString(obj);
+            String text = JsonMapper.toJsonString(obj);
             System.out.println(text);
-            JSON.parseObject(text, clazz);
+            JsonMapper.parseJsonObject(text, clazz);
         } finally {
             JSONFactory.setContextReaderCreator(null);
             JSONFactory.setContextWriterCreator(null);
         }
     }
-    
+
     public static class ExtClassLoader extends ClassLoader {
         public ExtClassLoader() throws IOException{
             super(Thread.currentThread().getContextClassLoader());
-            
+
             byte[] bytes;
             InputStream is = Thread.currentThread().getContextClassLoader().getResourceAsStream("external/VO.clazz");
             bytes = IOUtils.toByteArray(is);
             is.close();
-            
+
             super.defineClass("external.VO", bytes, 0, bytes.length);
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/TransientTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/TransientTest.java
index adc133c97..b95984f64 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/TransientTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/TransientTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.beans.Transient;
@@ -12,21 +12,21 @@ public class TransientTest {
     public void test_0() {
         A a = new A();
         a.id = 100;
-        assertEquals("{}", JSON.toJSONString(a));
+        assertEquals("{}", JsonMapper.toJsonString(a));
     }
 
     @Test
     public void test_1() {
         B b = new B();
         b.id = 100;
-        assertEquals("{}", JSON.toJSONString(b));
+        assertEquals("{}", JsonMapper.toJsonString(b));
     }
 
     @Test
     public void test_2() {
         C c = new C();
         c.id = 100;
-        assertEquals("{}", JSON.toJSONString(c));
+        assertEquals("{}", JsonMapper.toJsonString(c));
     }
 
     public static class A {
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/TypedMapTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/TypedMapTest.java
index 77b06bc7c..1cdbebae0 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/TypedMapTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/TypedMapTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -37,8 +37,8 @@ public class TypedMapTest {
         map.put("name", "DataWorks");
         a.setData(map);
 
-        String str = JSON.toJSONString(a, JSONWriter.Feature.ReferenceDetection, JSONWriter.Feature.WriteClassName);
-        A a1 = (A) JSON.parse(str, JSONReader.Feature.SupportAutoType);
+        String str = JsonMapper.toJsonString(a, JSONWriter.Feature.ReferenceDetection, JSONWriter.Feature.WriteClassName);
+        A a1 = (A) JsonMapper.parseJson(str, JSONReader.Feature.SupportAutoType);
         assertEquals(2, a1.data.size());
         assertEquals("1001", a1.data.get("id"));
         assertEquals("DataWorks", a1.data.get("name"));
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/UnicodeClassNameTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/UnicodeClassNameTest.java
index d1ce40a7a..216357f6e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/UnicodeClassNameTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/UnicodeClassNameTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static junit.framework.TestCase.assertEquals;
@@ -10,9 +10,9 @@ public class UnicodeClassNameTest {
     public void test_0() throws Exception {
         动物 vo = new 动物();
         vo.名称 = "盒马";
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"名称\":\"盒马\"}", str);
-        动物 vo1 = JSON.parseObject(str, 动物.class);
+        动物 vo1 = JsonMapper.parseJsonObject(str, 动物.class);
         assertEquals(vo.名称, vo1.名称);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/codec/WriteMapTest.java b/core/src/test/java/com/alibaba/fastjson2/codec/WriteMapTest.java
index 86074f2f7..513ac5a43 100644
--- a/core/src/test/java/com/alibaba/fastjson2/codec/WriteMapTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/codec/WriteMapTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.codec;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Collections;
@@ -11,22 +11,22 @@ import static junit.framework.TestCase.assertEquals;
 public class WriteMapTest {
     @Test
     public void test_HashMap() {
-        assertEquals("{}", JSON.toJSONString(new HashMap<>()));
+        assertEquals("{}", JsonMapper.toJsonString(new HashMap<>()));
     }
 
     @Test
     public void test_emptyMap() {
-        assertEquals("{}", JSON.toJSONString(Collections.emptyMap()));
+        assertEquals("{}", JsonMapper.toJsonString(Collections.emptyMap()));
     }
 
     @Test
     public void test_singletonMap() {
-        assertEquals("{\"id\":101}", JSON.toJSONString(Collections.singletonMap("id", 101)));
+        assertEquals("{\"id\":101}", JsonMapper.toJsonString(Collections.singletonMap("id", 101)));
     }
 
     @Test
     public void test_unmodifiableMap() {
-        assertEquals("{}", JSON.toJSONString(Collections.unmodifiableMap(new HashMap<>())));
+        assertEquals("{}", JsonMapper.toJsonString(Collections.unmodifiableMap(new HashMap<>())));
     }
 
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java b/core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java
index 5554e8e5a..f65eaebf9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java
@@ -3,7 +3,7 @@ package com.alibaba.fastjson2.eishay;
 import com.alibaba.fastjson2.eishay.vo.Image;
 import com.alibaba.fastjson2.eishay.vo.Media;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -95,7 +95,7 @@ public class ParserTest {
         jsonWriter.writeAny(o);
         System.out.println(jsonWriter);
         String arrayStr = jsonWriter.toString();
-        Object o2 = JSON.parseObject(arrayStr, MediaContent.class, JSONReader.Feature.SupportArrayToBean);
+        Object o2 = JsonMapper.parseJsonObject(arrayStr, MediaContent.class, JSONReader.Feature.SupportArrayToBean);
 //        js.wr
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest.java b/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest.java
index fd03030c4..1af386e01 100644
--- a/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest.java
@@ -35,10 +35,10 @@ public class FieldBasedTest {
         A a = new A();
         a.id = 101;
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.FieldBased);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.FieldBased);
         assertEquals("{\"id\":101}", json);
 
-        A a1 = JSON.parseObject(json, A.class, JSONReader.Feature.FieldBased);
+        A a1 = JsonMapper.parseJsonObject(json, A.class, JSONReader.Feature.FieldBased);
         assertEquals(a.id, a1.id);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest2.java b/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest2.java
index f2bbc1fc4..7eae2acce 100644
--- a/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.fieldbased;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -21,7 +21,7 @@ public class FieldBasedTest2 {
         a.v9 = Collections.emptyMap();
         a.v10 = Collections.emptyList();
 
-        String str = JSON.toJSONString(a, JSONWriter.Feature.FieldBased);
+        String str = JsonMapper.toJsonString(a, JSONWriter.Feature.FieldBased);
         assertEquals("{\"v0\":0,\"v1\":0.0,\"v10\":[],\"v2\":0.0,\"v3\":\"A\",\"v4\":0,\"v5\":0,\"v6\":false,\"v7\":[101],\"v8\":[],\"v9\":{}}", str);
     }
     static class A {
diff --git a/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest3.java b/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest3.java
index 3f21d26a1..953692036 100644
--- a/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/fieldbased/FieldBasedTest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.fieldbased;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -12,9 +12,9 @@ public class FieldBasedTest3 {
     public void test_0() {
         A a = new A(101);
 
-        String str = JSON.toJSONString(a, JSONWriter.Feature.FieldBased);
+        String str = JsonMapper.toJsonString(a, JSONWriter.Feature.FieldBased);
         assertEquals("{\"id\":101}", str);
-        A a1 = JSON.parseObject(str, A.class, JSONReader.Feature.FieldBased);
+        A a1 = JsonMapper.parseJsonObject(str, A.class, JSONReader.Feature.FieldBased);
         assertEquals(a.id, a1.id);
     }
     public static class A {
diff --git a/core/src/test/java/com/alibaba/fastjson2/filter/FilterTest.java b/core/src/test/java/com/alibaba/fastjson2/filter/FilterTest.java
index 68e4186c5..698c96543 100644
--- a/core/src/test/java/com/alibaba/fastjson2/filter/FilterTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/filter/FilterTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.filter;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONArray;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
@@ -12,26 +12,26 @@ import static junit.framework.TestCase.*;
 public class FilterTest {
     @Test
     public void test_0() {
-        assertEquals("{\"Id\":123}", JSON.toJSONString(Collections.singletonMap("id", 123), new PascalNameFilter()));
-        assertEquals("{\"\":123}", JSON.toJSONString(Collections.singletonMap("", 123), new PascalNameFilter()));
+        assertEquals("{\"Id\":123}", JsonMapper.toJsonString(Collections.singletonMap("id", 123), new PascalNameFilter()));
+        assertEquals("{\"\":123}", JsonMapper.toJsonString(Collections.singletonMap("", 123), new PascalNameFilter()));
     }
 
     @Test
     public void test_1() {
         A a = new A();
         a.id = 123;
-        assertEquals("{\"Id\":123}", JSON.toJSONString(a, new PascalNameFilter()));
+        assertEquals("{\"Id\":123}", JsonMapper.toJsonString(a, new PascalNameFilter()));
     }
 
     @Test
     public void test_2() {
-        assertEquals("{\"id\":123}", JSON.toJSONString(
+        assertEquals("{\"id\":123}", JsonMapper.toJsonString(
                 new JSONObject()
                 .fluentPut("id", 123)
                 .fluentPut("name", "DataWorks")
                 , new SimplePropertyPreFilter("id")));
 
-        assertEquals("{\"id\":123,\"name\":\"DataWorks\"}", JSON.toJSONString(
+        assertEquals("{\"id\":123,\"name\":\"DataWorks\"}", JsonMapper.toJsonString(
                 new JSONObject()
                         .fluentPut("id", 123)
                         .fluentPut("name", "DataWorks")
@@ -46,7 +46,7 @@ public class FilterTest {
         filter.setMaxLevel(1);
         assertEquals(1, filter.getMaxLevel());
         assertEquals("{\"value\":{}}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new JSONObject()
                                 .fluentPut("value"
                                         , new JSONObject()
@@ -60,7 +60,7 @@ public class FilterTest {
     public void test_4() {
         SimplePropertyPreFilter filter = new SimplePropertyPreFilter();
         filter.getExcludes().add("name");
-        assertEquals("{\"id\":123}", JSON.toJSONString(
+        assertEquals("{\"id\":123}", JsonMapper.toJsonString(
                 new JSONObject()
                         .fluentPut("id", 123)
                         .fluentPut("name", "DataWorks")
@@ -71,7 +71,7 @@ public class FilterTest {
     public void test_5() {
         SimplePropertyPreFilter filter = new SimplePropertyPreFilter();
         filter.getIncludes().add("name");
-        assertEquals("{\"name\":\"DataWorks\"}", JSON.toJSONString(
+        assertEquals("{\"name\":\"DataWorks\"}", JsonMapper.toJsonString(
                 new JSONObject()
                         .fluentPut("id", 123)
                         .fluentPut("name", "DataWorks")
@@ -83,7 +83,7 @@ public class FilterTest {
         SimplePropertyPreFilter filter = new SimplePropertyPreFilter(JSONArray.class);
         assertNotNull(filter.getClazz());
         assertEquals("{}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new JSONObject()
                                 .fluentPut("value"
                                         , new JSONObject()
diff --git a/core/src/test/java/com/alibaba/fastjson2/hsf/HSFTest.java b/core/src/test/java/com/alibaba/fastjson2/hsf/HSFTest.java
index ce2521e9b..1dd57a2bd 100644
--- a/core/src/test/java/com/alibaba/fastjson2/hsf/HSFTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/hsf/HSFTest.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.hsf;
 
 import com.alibaba.fastjson.JSONObject;
-import com.alibaba.fastjson2.JSON;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
diff --git a/core/src/test/java/com/alibaba/fastjson2/issues/Issue27.java b/core/src/test/java/com/alibaba/fastjson2/issues/Issue27.java
index 1017d4d83..01f937c86 100644
--- a/core/src/test/java/com/alibaba/fastjson2/issues/Issue27.java
+++ b/core/src/test/java/com/alibaba/fastjson2/issues/Issue27.java
@@ -1,7 +1,7 @@
 package com.alibaba.fastjson2.issues;
 
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -15,9 +15,9 @@ public class Issue27 {
         HashMap<Object, Object> hashMap = new HashMap<>();
         hashMap.put("1",a);
 
-        String string = JSON.toJSONString(hashMap);
+        String string = JsonMapper.toJsonString(hashMap);
         assertEquals("{\"1\":\"\\\\\"}", string);
-        JSON.parse(string);
+        JsonMapper.parseJson(string);
     }
 
     @Test
@@ -26,8 +26,8 @@ public class Issue27 {
         HashMap<Object, Object> hashMap = new HashMap<>();
         hashMap.put("1",a);
 
-        String string = JSON.toJSONString(hashMap);
+        String string = JsonMapper.toJsonString(hashMap);
         assertEquals("{\"1\":\"\\\"\"}", string);
-        JSON.parse(string);
+        JsonMapper.parseJson(string);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/issues/Issue28.java b/core/src/test/java/com/alibaba/fastjson2/issues/Issue28.java
index 84324b31e..073c447d0 100644
--- a/core/src/test/java/com/alibaba/fastjson2/issues/Issue28.java
+++ b/core/src/test/java/com/alibaba/fastjson2/issues/Issue28.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.issues;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.TypeReference;
 import org.junit.jupiter.api.Test;
 
@@ -11,7 +11,7 @@ public class Issue28 {
     public void test_generic() {
         String str = "{}";
 
-        Result result = JSON.parseObject(str, new TypeReference<Result>(){});
+        Result result = JsonMapper.parseJsonObject(str, new TypeReference<Result>(){});
         assertNotNull(result);
     }
 
@@ -19,7 +19,7 @@ public class Issue28 {
     public void test_generic_1() {
         String str = "{}";
 
-        Result result = JSON.parseObject(str, new TypeReference<Result>(){}.getType());
+        Result result = JsonMapper.parseJsonObject(str, new TypeReference<Result>(){}.getType());
         assertNotNull(result);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/issues/Issue37.java b/core/src/test/java/com/alibaba/fastjson2/issues/Issue37.java
index f68020d12..9281f5add 100644
--- a/core/src/test/java/com/alibaba/fastjson2/issues/Issue37.java
+++ b/core/src/test/java/com/alibaba/fastjson2/issues/Issue37.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.issues;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -14,10 +14,10 @@ public class Issue37 {
     @Test
     public void test_for_issue() {
         String str = "{\"test\":\"123465\"}";
-        JSONObject json = JSON.parseObject(str);
+        JSONObject json = JsonMapper.parseJsonObject(str);
         assertEquals(1, json.toJavaObject(Map.class).size());
-        assertEquals(1, JSON.toJavaObject(json, Map.class).size());
-        assertEquals(1, JSON.toJavaObject(str, Map.class).size());
+        assertEquals(1, JsonMapper.convertToJavaObject(json, Map.class).size());
+        assertEquals(1, JsonMapper.convertToJavaObject(str, Map.class).size());
 
         {
             HashMap map = json.toJavaObject(HashMap.class);
diff --git a/core/src/test/java/com/alibaba/fastjson2/issues/Issue9.java b/core/src/test/java/com/alibaba/fastjson2/issues/Issue9.java
index 66845a7bd..bef889857 100644
--- a/core/src/test/java/com/alibaba/fastjson2/issues/Issue9.java
+++ b/core/src/test/java/com/alibaba/fastjson2/issues/Issue9.java
@@ -1,8 +1,6 @@
 package com.alibaba.fastjson2.issues;
 
-import com.alibaba.fastjson.parser.Feature;
-import com.alibaba.fastjson2.JSON;
-import com.alibaba.fastjson2.JSONReader;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -15,7 +13,7 @@ public class Issue9 {
         p.id = 101;
         p.name = "DataWorks";
 
-        String str = JSON.toJSONString(p);
+        String str = JsonMapper.toJsonString(p);
         assertEquals("{\"name\":\"DataWorks\",\"id\":101}", str);
     }
 
@@ -34,9 +32,9 @@ public class Issue9 {
         b.id = 101;
         b.name = "DataWorks";
 
-        String str = JSON.toJSONString(b);
+        String str = JsonMapper.toJsonString(b);
         assertEquals("{\"BName\":\"DataWorks\",\"id\":101}", str);
-        B b1 = JSON.parseObject(str, B.class);
+        B b1 = JsonMapper.parseJsonObject(str, B.class);
         assertEquals(b.id, b1.id);
         assertEquals(b.name, b1.name);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/jackson_cve/CVE_2020_36518.java b/core/src/test/java/com/alibaba/fastjson2/jackson_cve/CVE_2020_36518.java
index 2cf8d5590..fdd1cc411 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jackson_cve/CVE_2020_36518.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jackson_cve/CVE_2020_36518.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.jackson_cve;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.List;
@@ -14,14 +14,14 @@ public class CVE_2020_36518 {
     @Test
     public void testWithArray() throws Exception {
         final String doc = _nestedDoc(TOO_DEEP_NESTING, "[ ", "] ");
-        Object ob = JSON.parseObject(doc, Object.class);
+        Object ob = JsonMapper.parseJsonObject(doc, Object.class);
         assertTrue(ob instanceof List<?>);
     }
 
     @Test
     public void testWithObject() throws Exception {
         final String doc = "{" + _nestedDoc(TOO_DEEP_NESTING, "\"x\":{", "} ") + "}";
-        Object ob = JSON.parseObject(doc, Object.class);
+        Object ob = JsonMapper.parseJsonObject(doc, Object.class);
         assertTrue(ob instanceof Map<?, ?>);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_10_contains.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_10_contains.java
index 946ee0915..6d21c1078 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_10_contains.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_10_contains.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.jsonpath;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertFalse;
@@ -53,7 +52,7 @@ public class JSONPath_10_contains {
                 "        ]\n" +
                 "    }\n" +
                 "}";
-        JSONObject root = JSON.parseObject(json);
+        JSONObject root = JsonMapper.parseJsonObject(json);
         assertTrue(
                 JSONPath.of("$.queryScene.scene.queryDataSet.dataSet")
                         .contains(root));
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_13.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_13.java
index 6686e98fe..9c96ae34d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_13.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_13.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.jsonpath;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -20,7 +19,7 @@ public class JSONPath_13 {
         JSONPath.of("$..id")
                 .remove(root);
 
-        assertEquals("{\"company\":{\"name\":\"jobs\"}}", JSON.toJSONString(root));
+        assertEquals("{\"company\":{\"name\":\"jobs\"}}", JsonMapper.toJsonString(root));
     }
 
     @Test
@@ -33,7 +32,7 @@ public class JSONPath_13 {
         JSONPath.of("$..id")
                 .remove(root);
 
-        assertEquals("{\"company\":{\"name\":\"jobs\"}}", JSON.toJSONString(root));
+        assertEquals("{\"company\":{\"name\":\"jobs\"}}", JsonMapper.toJsonString(root));
     }
 
     public static class Root {
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_15.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_15.java
index 9317d1195..29fd532b8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_15.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_15.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.jsonpath;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -29,26 +28,26 @@ public class JSONPath_15 {
 
     @Test
     public void test_min() {
-        Object object = JSON.parse(b);
+        Object object = JsonMapper.parseJson(b);
 
         Object min = JSONPath.eval(object, "$..c.min()");
-        assertEquals("1", JSON.toJSONString(min));
+        assertEquals("1", JsonMapper.toJsonString(min));
     }
 
     @Test
     public void test_max() {
-        Object object = JSON.parse(b);
+        Object object = JsonMapper.parseJson(b);
 
         Object min = JSONPath.eval(object, "$..c.max()");
-        assertEquals("23", JSON.toJSONString(min));
+        assertEquals("23", JsonMapper.toJsonString(min));
     }
 
     @Test
     public void test_3() {
-        Object object = JSON.parse(c);
+        Object object = JsonMapper.parseJson(c);
 
         Object min = JSONPath.eval(object, "$[?(@.c =~ /a+/)]");
-        assertEquals("[{\"c\":\"aaaa\"}]", JSON.toJSONString(min));
+        assertEquals("[{\"c\":\"aaaa\"}]", JsonMapper.toJsonString(min));
     }
 //
 //    public void test_c() {
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_16.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_16.java
index 4470f6e5e..43877317b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_16.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_16.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.jsonpath;
 
 import com.alibaba.fastjson2.*;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.math.BigDecimal;
@@ -64,7 +63,7 @@ public class JSONPath_16 {
                                 JSONReader.of(str))
         );
 
-        assertEquals(JSON.parseObject(str),
+        assertEquals(JsonMapper.parseJsonObject(str),
                 JSONPath.extract(str, "$[?( @.salary > 1000 )]"));
     }
 
@@ -74,14 +73,14 @@ public class JSONPath_16 {
         Object object = JSONPath.of("$[? (@.type() = \"array\")]")
                 .extract(
                         JSONReader.of(str));
-        assertEquals("[[10,20],[100]]", JSON.toJSONString(object));
+        assertEquals("[[10,20],[100]]", JsonMapper.toJsonString(object));
     }
 
     @Test
     public void test_for_jsonpath_3() throws Exception {
         String str = "[[10,20],[100]]";
         Object object = JSONPath.extract(str, "$[? (@.size() > 1)]");
-        assertEquals("[[10,20]]", JSON.toJSONString(object));
+        assertEquals("[[10,20]]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -90,7 +89,7 @@ public class JSONPath_16 {
                 new Object[] {10, 20}, new Object[] {100}
         );
         Object object = JSONPath.of("$[? (@.size() > 1)]").eval(root);
-        assertEquals("[[10,20]]", JSON.toJSONString(object));
+        assertEquals("[[10,20]]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -99,7 +98,7 @@ public class JSONPath_16 {
                 new Object[]{10, 20}, new Object[]{100}
         };
         Object object = JSONPath.of("$[? (@.size() > 1)]").eval(root);
-        assertEquals("[[10,20]]", JSON.toJSONString(object));
+        assertEquals("[[10,20]]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -108,7 +107,7 @@ public class JSONPath_16 {
         Object object = JSONPath.of("$[? (@.type() = 'array' && @.size() > 1)]")
                 .extract(
                         JSONReader.of(str));
-        assertEquals("[[10,20]]", JSON.toJSONString(object));
+        assertEquals("[[10,20]]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -117,7 +116,7 @@ public class JSONPath_16 {
         Object object = JSONPath.of("$[? (@.type() = 'array' and @.size() > 1)]")
                 .extract(
                         JSONReader.of(str));
-        assertEquals("[[10,20]]", JSON.toJSONString(object));
+        assertEquals("[[10,20]]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -126,7 +125,7 @@ public class JSONPath_16 {
         Object object = JSONPath.of("$[? (@.type() = 'object' || @.size() > 1)]")
                 .extract(
                         JSONReader.of(str));
-        assertEquals("[[10,20],{\"id\":1001}]", JSON.toJSONString(object));
+        assertEquals("[[10,20],{\"id\":1001}]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -135,7 +134,7 @@ public class JSONPath_16 {
         Object object = JSONPath.of("$[? (@.size() >= 2)]")
                 .extract(
                         JSONReader.of(str));
-        assertEquals("[[10,20]]", JSON.toJSONString(object));
+        assertEquals("[[10,20]]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -144,7 +143,7 @@ public class JSONPath_16 {
         Object object = JSONPath.of("$[? (@.type() = 'object' or @.size() > 1)]")
                 .extract(
                         JSONReader.of(str));
-        assertEquals("[[10,20],{\"id\":1001}]", JSON.toJSONString(object));
+        assertEquals("[[10,20],{\"id\":1001}]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -154,7 +153,7 @@ public class JSONPath_16 {
                 .of("$.readings.floor()")
                 .extract(
                         JSONReader.of(str));
-        assertEquals("[15,-23,45]", JSON.toJSONString(object));
+        assertEquals("[15,-23,45]", JsonMapper.toJsonString(object));
     }
 
     @Test
@@ -164,7 +163,7 @@ public class JSONPath_16 {
                 .of("$.floor()")
                 .extract(
                         JSONReader.of(str));
-        assertEquals("[15,-23,45]", JSON.toJSONString(object));
+        assertEquals("[15,-23,45]", JsonMapper.toJsonString(object));
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_4.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_4.java
index fc5e1236f..d018a8abc 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_4.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_4.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.jsonpath;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.Assert;
 import org.junit.jupiter.api.Test;
 
@@ -11,7 +10,7 @@ public class JSONPath_4 {
     @Test
     public void test_path() throws Exception {
         String a = "{\"key\":\"value\",\"10.0.1.1\":\"haha\"}";
-        Object x = JSON.parse(a);
+        Object x = JsonMapper.parseJson(a);
         JSONPath.set(x, "$.test", "abc");
         Object o = JSONPath.eval(x, "$.10\\.0\\.1\\.1");
         Assert.assertEquals("haha", o);
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_min_max.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_min_max.java
index 7491d02ac..274575ecc 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_min_max.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/JSONPath_min_max.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.jsonpath;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONPath;
 import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
@@ -22,11 +22,11 @@ public class JSONPath_min_max {
     public void test_1() {
         Object[] array = new Object[] {"1", 2f, 3D, 4};
         TestCase.assertEquals("\"1\""
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(array)));
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(array)));
     }
@@ -35,11 +35,11 @@ public class JSONPath_min_max {
     public void test_2() {
         Object[] array = new Object[] {"21474836480", 2f, 3D, 4};
         assertEquals("2.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(array)));
         assertEquals("\"21474836480\""
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(array)));
     }
@@ -49,11 +49,11 @@ public class JSONPath_min_max {
     public void test_3() {
         Object[] array = new Object[] {"214748364802147483648021474836480", 3D, 4};
         assertEquals("3.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(array)));
         assertEquals("\"214748364802147483648021474836480\""
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(array)));
     }
@@ -65,11 +65,11 @@ public class JSONPath_min_max {
                 , BigInteger.valueOf(3)
                 , BigDecimal.valueOf(4), 5F, 6D, 7, 8L, BigInteger.valueOf(9), BigDecimal.valueOf(10), 11L, 12D};
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(array)));
         assertEquals("\"214748364802147483648021474836480\""
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(array)));
     }
@@ -77,56 +77,56 @@ public class JSONPath_min_max {
     @Test
     public void test_5() {
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), 3})));
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), 3})));
 
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), 3L})));
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), 3L})));
 
         assertEquals("3.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), 3F})));
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), 3F})));
 
         assertEquals("3.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), 3D})));
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), 3D})));
 
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), BigInteger.valueOf(3)})));
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { BigDecimal.valueOf(4), BigInteger.valueOf(3)})));
@@ -135,42 +135,42 @@ public class JSONPath_min_max {
     @Test
     public void test_6() {
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[]{4L, 3})));
 
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4L, 3})));
 
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[]{4L, BigDecimal.valueOf(3)})));
 
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4L, BigInteger.valueOf(3)})));
 
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4L, 3F})));
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4L, 3D})));
 
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4L, "3"})));
@@ -179,42 +179,42 @@ public class JSONPath_min_max {
     @Test
     public void test_7() {
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[]{4, 3L})));
 
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4, 3})));
 
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[]{4, BigDecimal.valueOf(3)})));
 
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4, BigInteger.valueOf(3)})));
 
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4, 3F})));
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4, 3D})));
 
         assertEquals("4"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4, "3"})));
@@ -223,42 +223,42 @@ public class JSONPath_min_max {
     @Test
     public void test_8_float() {
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[]{4F, 3L})));
 
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4F, 3})));
 
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[]{4F, BigDecimal.valueOf(3)})));
 
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4F, BigInteger.valueOf(3)})));
 
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4F, 3F})));
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4F, 3D})));
 
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4F, "3"})));
@@ -267,37 +267,37 @@ public class JSONPath_min_max {
     @Test
     public void test_9_double() {
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[]{4D, 3L})));
 
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4D, 3})));
 
         assertEquals("3"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.min()")
                                 .eval(
                                         new Object[]{4D, BigDecimal.valueOf(3)})));
 
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4D, BigInteger.valueOf(3)})));
 
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4D, 3F})));
 
         assertEquals("4.0"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONPath.of("$.max()")
                                 .eval(
                                         new Object[] { 4D, "3"})));
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathJSONBTest.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathJSONBTest.java
index 736b1b5d9..503ab8097 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathJSONBTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathJSONBTest.java
@@ -21,7 +21,7 @@ public class PathJSONBTest {
         InputStream is = Int2Test.class.getClassLoader().getResourceAsStream("data/path_01.json");
         str = IOUtils.toString(is, "UTF-8");
         byte[] utf8Bytes = str.getBytes(StandardCharsets.UTF_8);
-        rootObject = JSON.parseObject(str);
+        rootObject = JsonMapper.parseJsonObject(str);
         jsonbBytes = JSONB.toBytes(rootObject);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathJSONBTest2.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathJSONBTest2.java
index 5b5c612d6..f3201552b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathJSONBTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathJSONBTest2.java
@@ -21,7 +21,7 @@ public class PathJSONBTest2 {
         InputStream is = Int2Test.class.getClassLoader().getResourceAsStream("data/path_02.json");
         str = IOUtils.toString(is, "UTF-8");
         byte[] utf8Bytes = str.getBytes(StandardCharsets.UTF_8);
-        rootObject = JSON.parseObject(str);
+        rootObject = JsonMapper.parseJsonObject(str);
         jsonbBytes = JSONB.toBytes(rootObject);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest.java
index 606edca33..a25dc47d1 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest.java
@@ -21,7 +21,7 @@ public class PathTest {
         InputStream is = Int2Test.class.getClassLoader().getResourceAsStream("data/path_01.json");
         str = IOUtils.toString(is, "UTF-8");
         utf8Bytes = str.getBytes(StandardCharsets.UTF_8);
-        rootObject = JSON.parseObject(str);
+        rootObject = JsonMapper.parseJsonObject(str);
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest2.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest2.java
index e8e0fa49d..328032369 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.jsonpath;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONPath;
 import com.alibaba.fastjson2.JSONReader;
@@ -21,7 +21,7 @@ public class PathTest2 {
     public PathTest2() throws Exception {
         InputStream is = Int2Test.class.getClassLoader().getResourceAsStream("data/path_02.json");
         str = IOUtils.toString(is, "UTF-8");
-        rootObject = JSON.parseObject(str);
+        rootObject = JsonMapper.parseJsonObject(str);
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest3.java b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest3.java
index 218c4eefc..5053779fd 100644
--- a/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/jsonpath/PathTest3.java
@@ -125,7 +125,7 @@ public class PathTest3 {
     @Test
     public void test_2() {
         Integer[] values = new Integer[] {1, 2, 3};
-        String jsonString = JSON.toJSONString(values);
+        String jsonString = JsonMapper.toJsonString(values);
 
         assertEquals(values[0], JSONPath.of("$[0]").extract(JSONReader.of(jsonString)));
         assertEquals("[1,2]"
diff --git a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest.java b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest.java
index f7230671d..6e0ce05a1 100644
--- a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.mixins;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -56,11 +56,11 @@ public class MixinAPITest {
     public void test_mixIn_get_methods() throws Exception {
         BaseClass base = new BaseClass(1, 2);
 
-        JSON.mixIn(BaseClass.class, MixIn1.class);
+        JsonMapper.addMixIn(BaseClass.class, MixIn1.class);
 
-        String str = JSON.toJSONString(base);
+        String str = JsonMapper.toJsonString(base);
 //        assertEquals("{\"apple\":1,\"banana\":2}", str);
-        BaseClass base2 = JSON.parseObject(str, BaseClass.class);
+        BaseClass base2 = JsonMapper.parseJsonObject(str, BaseClass.class);
         assertEquals(base.a, base2.a);
         assertEquals(base.b, base2.b);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest1.java b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest1.java
index 1e18bcfb5..0d2febbeb 100644
--- a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest1.java
+++ b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest1.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.mixins;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -33,11 +33,11 @@ public class MixinAPITest1 {
     public void test_mixIn_get_methods() throws Exception {
         BaseClass base = new BaseClass(1, 2);
 
-        JSON.mixIn(BaseClass.class, MixIn1.class);
+        JsonMapper.addMixIn(BaseClass.class, MixIn1.class);
 
-        String str = JSON.toJSONString(base);
+        String str = JsonMapper.toJsonString(base);
         assertEquals("{\"apple\":1,\"banana\":2}", str);
-        BaseClass base2 = JSON.parseObject(str, BaseClass.class);
+        BaseClass base2 = JsonMapper.parseJsonObject(str, BaseClass.class);
         assertEquals(base.a, base2.a);
         assertEquals(base.b, base2.b);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest2.java b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest2.java
index ff191a7c9..8047b77fe 100644
--- a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.mixins;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -35,11 +35,11 @@ public class MixinAPITest2 {
     public void test_mixIn_get_methods() throws Exception {
         BaseClass base = new BaseClass(1, 2);
 
-        JSON.mixIn(BaseClass.class, MixIn1.class);
+        JsonMapper.addMixIn(BaseClass.class, MixIn1.class);
 
-        String str = JSON.toJSONString(base);
+        String str = JsonMapper.toJsonString(base);
         assertEquals("{\"apple\":1,\"banana\":2}", str);
-        BaseClass base2 = JSON.parseObject(str, BaseClass.class);
+        BaseClass base2 = JsonMapper.parseJsonObject(str, BaseClass.class);
         assertEquals(base.a, base2.a);
         assertEquals(base.b, base2.b);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest3.java b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest3.java
index 56dec7045..4b5c6c729 100644
--- a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.mixins;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -35,11 +35,11 @@ public class MixinAPITest3 {
     public void test_mixIn_get_methods() throws Exception {
         BaseClass base = new BaseClass(1, 2);
 
-        JSON.mixIn(BaseClass.class, MixIn1.class);
+        JsonMapper.addMixIn(BaseClass.class, MixIn1.class);
 
-        String str = JSON.toJSONString(base);
+        String str = JsonMapper.toJsonString(base);
         assertEquals("{\"apple\":1,\"banana\":2}", str);
-        BaseClass base2 = JSON.parseObject(str, BaseClass.class);
+        BaseClass base2 = JsonMapper.parseJsonObject(str, BaseClass.class);
         assertEquals(base.a, base2.a);
         assertEquals(base.b, base2.b);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest4.java b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest4.java
index 6fe11b951..27aa2764c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest4.java
+++ b/core/src/test/java/com/alibaba/fastjson2/mixins/MixinAPITest4.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.mixins;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -40,11 +40,11 @@ public class MixinAPITest4 {
     public void test_mixIn_get_methods() throws Exception {
         BaseClass base = new BaseClass(1, 2);
 
-        JSON.mixIn(BaseClass.class, MixIn1.class);
+        JsonMapper.addMixIn(BaseClass.class, MixIn1.class);
 
-        String str = JSON.toJSONString(base);
+        String str = JsonMapper.toJsonString(base);
         assertEquals("{\"apple\":1,\"banana\":2}", str);
-        BaseClass base2 = JSON.parseObject(str, BaseClass.class);
+        BaseClass base2 = JsonMapper.parseJsonObject(str, BaseClass.class);
         assertEquals(base.a, base2.a);
         assertEquals(base.b, base2.b);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/money/MonetaryTest.java b/core/src/test/java/com/alibaba/fastjson2/money/MonetaryTest.java
index 2837659e7..280e16d0d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/money/MonetaryTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/money/MonetaryTest.java
@@ -1,13 +1,12 @@
 package com.alibaba.fastjson2.money;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.javamoney.moneta.Money;
 import org.junit.jupiter.api.Test;
 
 import javax.money.CurrencyUnit;
 import javax.money.Monetary;
 import javax.money.MonetaryAmount;
-import javax.money.NumberValue;
 
 import static org.junit.Assert.assertEquals;
 
@@ -15,9 +14,9 @@ public class MonetaryTest {
     @Test
     public void test_unit() {
         CurrencyUnit usd = Monetary.getCurrency("USD");
-        String str = JSON.toJSONString(usd);
+        String str = JsonMapper.toJsonString(usd);
         assertEquals("\"USD\"", str);
-        CurrencyUnit usd2 = JSON.parseObject(str, CurrencyUnit.class);
+        CurrencyUnit usd2 = JsonMapper.parseJsonObject(str, CurrencyUnit.class);
         assertEquals(usd, usd2);
     }
 
@@ -27,19 +26,19 @@ public class MonetaryTest {
         MonetaryAmount amount = Monetary.getDefaultAmountFactory()
                 .setCurrency(usd).setNumber(200).create();
 
-        String str = JSON.toJSONString(amount);
+        String str = JsonMapper.toJsonString(amount);
         assertEquals("{\"currency\":\"USD\",\"number\":200}", str);
 
-        MonetaryAmount amount2 = JSON.parseObject(str, MonetaryAmount.class);
+        MonetaryAmount amount2 = JsonMapper.parseJsonObject(str, MonetaryAmount.class);
         assertEquals(amount, amount2);
     }
 
     @Test
     public void test_money() {
         Money oneEuro = Money.of(1, "EUR");
-        String str = JSON.toJSONString(oneEuro);
+        String str = JsonMapper.toJsonString(oneEuro);
         System.out.println(str);
-        Money money = JSON.parseObject(str, Money.class);
+        Money money = JsonMapper.parseJsonObject(str, Money.class);
         assertEquals(oneEuro, money);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/AtomicIntegerArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/AtomicIntegerArrayTest.java
index 5c1af74ac..5b3e7d43d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/AtomicIntegerArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/AtomicIntegerArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -14,7 +14,7 @@ import static junit.framework.TestCase.assertNull;
 public class AtomicIntegerArrayTest {
     @Test
     public void test_parse_null() {
-        AtomicIntegerArray values = JSON.parseObject("null", AtomicIntegerArray.class);
+        AtomicIntegerArray values = JsonMapper.parseJsonObject("null", AtomicIntegerArray.class);
         assertNull(values);
     }
 
@@ -26,7 +26,7 @@ public class AtomicIntegerArrayTest {
 
     @Test
     public void test_parse() {
-        AtomicIntegerArray array = JSON.parseObject("[101,null,102]", AtomicIntegerArray.class);
+        AtomicIntegerArray array = JsonMapper.parseJsonObject("[101,null,102]", AtomicIntegerArray.class);
         assertEquals(3, array.length());
         assertEquals(101, array.get(0));
         assertEquals(0, array.get(1));
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/AtomicLongArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/AtomicLongArrayTest.java
index 5b2c2824f..ba4f13696 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/AtomicLongArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/AtomicLongArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -14,7 +14,7 @@ import static junit.framework.TestCase.assertNull;
 public class AtomicLongArrayTest {
     @Test
     public void test_parse_null() {
-        AtomicLongArray values = JSON.parseObject("null", AtomicLongArray.class);
+        AtomicLongArray values = JsonMapper.parseJsonObject("null", AtomicLongArray.class);
         assertNull(values);
     }
 
@@ -26,7 +26,7 @@ public class AtomicLongArrayTest {
 
     @Test
     public void test_parse() {
-        AtomicLongArray array = JSON.parseObject("[101,null,102]", AtomicLongArray.class);
+        AtomicLongArray array = JsonMapper.parseJsonObject("[101,null,102]", AtomicLongArray.class);
         assertEquals(3, array.length());
         assertEquals(101, array.get(0));
         assertEquals(0, array.get(1));
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/BigDecimalTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/BigDecimalTest.java
index 6b5279d30..e34d609cb 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/BigDecimalTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/BigDecimalTest.java
@@ -171,9 +171,9 @@ public class BigDecimalTest {
         for (BigDecimal id : values) {
             BigDecimal1 vo = new BigDecimal1();
             vo.setId(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            BigDecimal1 v1 = JSON.parseObject(utf8Bytes, BigDecimal1.class);
+            BigDecimal1 v1 = JsonMapper.parseJsonObject(utf8Bytes, BigDecimal1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -181,8 +181,8 @@ public class BigDecimalTest {
     @Test
     public void test_utf8_value() {
         for (BigDecimal id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            BigDecimal id2 = JSON.parseObject(utf8Bytes, BigDecimal.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            BigDecimal id2 = JsonMapper.parseJsonObject(utf8Bytes, BigDecimal.class);
             assertEquals(id, id2);
         }
     }
@@ -192,9 +192,9 @@ public class BigDecimalTest {
         for (BigDecimal id : values) {
             BigDecimal1 vo = new BigDecimal1();
             vo.setId(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            BigDecimal1 v1 = JSON.parseObject(str, BigDecimal1.class);
+            BigDecimal1 v1 = JsonMapper.parseJsonObject(str, BigDecimal1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -202,8 +202,8 @@ public class BigDecimalTest {
     @Test
     public void test_str_value() {
         for (BigDecimal id : values) {
-            String str = JSON.toJSONString(id);
-            BigDecimal id2 = JSON.parseObject(str, BigDecimal.class);
+            String str = JsonMapper.toJsonString(id);
+            BigDecimal id2 = JsonMapper.parseJsonObject(str, BigDecimal.class);
             assertEquals(id, id2);
         }
     }
@@ -213,9 +213,9 @@ public class BigDecimalTest {
         for (BigDecimal id : values) {
             BigDecimal1 vo = new BigDecimal1();
             vo.setId(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            BigDecimal1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, BigDecimal1.class);
+            BigDecimal1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, BigDecimal1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -223,8 +223,8 @@ public class BigDecimalTest {
     @Test
     public void test_ascii_value() {
         for (BigDecimal id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            BigDecimal id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, BigDecimal.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            BigDecimal id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, BigDecimal.class);
             assertEquals(id, id2);
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/BigIntegerTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/BigIntegerTest.java
index cf0bc9e55..4f7fc07ca 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/BigIntegerTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/BigIntegerTest.java
@@ -159,9 +159,9 @@ public class BigIntegerTest {
         for (BigInteger id : values) {
             BigInteger1 vo = new BigInteger1();
             vo.setId(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            BigInteger1 v1 = JSON.parseObject(utf8Bytes, BigInteger1.class);
+            BigInteger1 v1 = JsonMapper.parseJsonObject(utf8Bytes, BigInteger1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -169,8 +169,8 @@ public class BigIntegerTest {
     @Test
     public void test_utf8_value() {
         for (BigInteger id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            BigInteger id2 = JSON.parseObject(utf8Bytes, BigInteger.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            BigInteger id2 = JsonMapper.parseJsonObject(utf8Bytes, BigInteger.class);
             assertEquals(id, id2);
         }
     }
@@ -180,9 +180,9 @@ public class BigIntegerTest {
         for (BigInteger id : values) {
             BigInteger1 vo = new BigInteger1();
             vo.setId(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            BigInteger1 v1 = JSON.parseObject(str, BigInteger1.class);
+            BigInteger1 v1 = JsonMapper.parseJsonObject(str, BigInteger1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -190,8 +190,8 @@ public class BigIntegerTest {
     @Test
     public void test_str_value() {
         for (BigInteger id : values) {
-            String str = JSON.toJSONString(id);
-            BigInteger id2 = JSON.parseObject(str, BigInteger.class);
+            String str = JsonMapper.toJsonString(id);
+            BigInteger id2 = JsonMapper.parseJsonObject(str, BigInteger.class);
             assertEquals(id, id2);
         }
     }
@@ -201,9 +201,9 @@ public class BigIntegerTest {
         for (BigInteger id : values) {
             BigInteger1 vo = new BigInteger1();
             vo.setId(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            BigInteger1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, BigInteger1.class);
+            BigInteger1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, BigInteger1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -211,8 +211,8 @@ public class BigIntegerTest {
     @Test
     public void test_ascii_value() {
         for (BigInteger id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            BigInteger id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, BigInteger.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            BigInteger id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, BigInteger.class);
             assertEquals(id, id2);
         }
     }
@@ -256,7 +256,7 @@ public class BigIntegerTest {
 
     @Test
     public void test_direct() {
-        assertEquals("0", JSON.toJSONString(BigInteger.ZERO));
+        assertEquals("0", JsonMapper.toJsonString(BigInteger.ZERO));
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanArrayTest.java
index 7ed7f20c4..ac91d26ee 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -13,7 +13,7 @@ import static junit.framework.TestCase.assertNull;
 public class BooleanArrayTest {
     @Test
     public void test_parse_null() {
-        Boolean[] bytes = JSON.parseObject("null", Boolean[].class);
+        Boolean[] bytes = JsonMapper.parseJsonObject("null", Boolean[].class);
         assertNull(bytes);
     }
 
@@ -25,7 +25,7 @@ public class BooleanArrayTest {
 
     @Test
     public void test_parse() {
-        Boolean[] array = JSON.parseObject("[1,0,null,true,false]", Boolean[].class);
+        Boolean[] array = JsonMapper.parseJsonObject("[1,0,null,true,false]", Boolean[].class);
         assertEquals(5, array.length);
         assertEquals(Boolean.TRUE, array[0]);
         assertEquals(Boolean.FALSE, array[1]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanTest.java
index 87f79734a..017d2eb2b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -123,7 +123,7 @@ public class BooleanTest {
     @Test
     public void test_null() {
         assertNull(
-                JSON.parseObject("null", Boolean.class));
+                JsonMapper.parseJsonObject("null", Boolean.class));
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanTest2.java b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanTest2.java
index 97504d985..b1c4aaf64 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.TestUtils;
@@ -99,9 +99,9 @@ public class BooleanTest2 {
         for (Boolean id : values) {
             Boolean1 vo = new Boolean1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Boolean1 v1 = JSON.parseObject(utf8Bytes, Boolean1.class);
+            Boolean1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Boolean1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -111,9 +111,9 @@ public class BooleanTest2 {
         for (Boolean id : values) {
             Boolean1 vo = new Boolean1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+            Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -121,70 +121,70 @@ public class BooleanTest2 {
     @Test
     public void test_str_num_0() {
         String str = "{\"v0000\":0}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.FALSE, v1.getV0000());
     }
 
     @Test
     public void test_str_num_1() {
         String str = "{\"v0000\":1}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.TRUE, v1.getV0000());
     }
 
     @Test
     public void test_str_str_0() {
         String str = "{\"v0000\":\"0\"}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.FALSE, v1.getV0000());
     }
 
     @Test
     public void test_str_str_1() {
         String str = "{\"v0000\":\"1\"}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.TRUE, v1.getV0000());
     }
 
     @Test
     public void test_str_str_N() {
         String str = "{\"v0000\":\"N\"}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.FALSE, v1.getV0000());
     }
 
     @Test
     public void test_str_str_Y() {
         String str = "{\"v0000\":\"Y\"}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.TRUE, v1.getV0000());
     }
 
     @Test
     public void test_str_str_true() {
         String str = "{\"v0000\":\"true\"}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.TRUE, v1.getV0000());
     }
 
     @Test
     public void test_str_str_false() {
         String str = "{\"v0000\":\"false\"}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.FALSE, v1.getV0000());
     }
 
     @Test
     public void test_str_str_TRUE() {
         String str = "{\"v0000\":\"TRUE\"}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.TRUE, v1.getV0000());
     }
 
     @Test
     public void test_str_str_FALSE() {
         String str = "{\"v0000\":\"FALSE\"}";
-        Boolean1 v1 = JSON.parseObject(str, Boolean1.class);
+        Boolean1 v1 = JsonMapper.parseJsonObject(str, Boolean1.class);
         assertEquals(Boolean.FALSE, v1.getV0000());
     }
 
@@ -193,9 +193,9 @@ public class BooleanTest2 {
         for (Boolean id : values) {
             Boolean1 vo = new Boolean1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Boolean1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Boolean1.class);
+            Boolean1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Boolean1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanValueArrayTest.java
index 74a05e3b1..2cea1ce21 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -14,7 +14,7 @@ import static junit.framework.TestCase.assertNull;
 public class BooleanValueArrayTest {
     @Test
     public void test_parse_null() {
-        boolean[] bytes = JSON.parseObject("null", boolean[].class);
+        boolean[] bytes = JsonMapper.parseJsonObject("null", boolean[].class);
         assertNull(bytes);
     }
 
@@ -26,7 +26,7 @@ public class BooleanValueArrayTest {
 
     @Test
     public void test_parse() {
-        boolean[] array = JSON.parseObject("[1,0,false,true,false]", boolean[].class);
+        boolean[] array = JsonMapper.parseJsonObject("[1,0,false,true,false]", boolean[].class);
         assertEquals(5, array.length);
         assertEquals(true, array[0]);
         assertEquals(false, array[1]);
@@ -49,28 +49,28 @@ public class BooleanValueArrayTest {
     @Test
     public void test_writeNull_0() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO()));
+                , JsonMapper.toJsonString(new VO()));
         assertEquals("{}",
                 new String(
-                        JSON.toJSONBytes(new VO())));
+                        JsonMapper.toJsonBytes(new VO())));
     }
 
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
     }
 
     @Test
     public void test_writeNull2() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO2(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO2(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
     }
 
     public static class VO {
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanValueFieldTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanValueFieldTest.java
index 05787853b..00645c391 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanValueFieldTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/BooleanValueFieldTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.reader.ObjectReader;
@@ -91,10 +91,10 @@ public class BooleanValueFieldTest {
         A a = new A();
         a.value = true;
 
-        String str = JSON.toJSONString(a, JSONWriter.Feature.FieldBased);
+        String str = JsonMapper.toJsonString(a, JSONWriter.Feature.FieldBased);
         assertEquals("{\"value\":true}", str);
 
-        A a1 = JSON.parseObject(str, A.class, JSONReader.Feature.FieldBased);
+        A a1 = JsonMapper.parseJsonObject(str, A.class, JSONReader.Feature.FieldBased);
         assertEquals(a.value, a1.value);
     }
 
@@ -103,10 +103,10 @@ public class BooleanValueFieldTest {
         B b = new B();
         b.value = true;
 
-        String str = JSON.toJSONString(b, JSONWriter.Feature.FieldBased);
+        String str = JsonMapper.toJsonString(b, JSONWriter.Feature.FieldBased);
         assertEquals("{\"value\":true}", str);
 
-        B b1 = JSON.parseObject(str, B.class, JSONReader.Feature.FieldBased);
+        B b1 = JsonMapper.parseJsonObject(str, B.class, JSONReader.Feature.FieldBased);
         assertEquals(b.value, b1.value);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/ByteTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/ByteTest.java
index 6e81137e9..b9ba89765 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/ByteTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/ByteTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2.JSONWriter;
@@ -232,9 +232,9 @@ public class ByteTest {
         for (Byte id : values) {
             Byte1 vo = new Byte1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Byte1 v1 = JSON.parseObject(utf8Bytes, Byte1.class);
+            Byte1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Byte1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -242,16 +242,16 @@ public class ByteTest {
     @Test
     public void test_utf8_value() {
         for (Byte id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Byte id2 = JSON.parseObject(utf8Bytes, Byte.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Byte id2 = JsonMapper.parseJsonObject(utf8Bytes, Byte.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_utf8_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Byte[] id2 = JSON.parseObject(utf8Bytes, Byte[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Byte[] id2 = JsonMapper.parseJsonObject(utf8Bytes, Byte[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -263,9 +263,9 @@ public class ByteTest {
         for (Byte id : values) {
             Byte1 vo = new Byte1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Byte1 v1 = JSON.parseObject(str, Byte1.class);
+            Byte1 v1 = JsonMapper.parseJsonObject(str, Byte1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -273,16 +273,16 @@ public class ByteTest {
     @Test
     public void test_str_value() {
         for (Byte id : values) {
-            String str = JSON.toJSONString(id);
-            Byte id2 = JSON.parseObject(str, Byte.class);
+            String str = JsonMapper.toJsonString(id);
+            Byte id2 = JsonMapper.parseJsonObject(str, Byte.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_str_array() {
-        String str = JSON.toJSONString(values);
-        Byte[] id2 = JSON.parseObject(str, Byte[].class);
+        String str = JsonMapper.toJsonString(values);
+        Byte[] id2 = JsonMapper.parseJsonObject(str, Byte[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -294,9 +294,9 @@ public class ByteTest {
         for (Byte id : values) {
             Byte1 vo = new Byte1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Byte1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Byte1.class);
+            Byte1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Byte1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -304,16 +304,16 @@ public class ByteTest {
     @Test
     public void test_ascii_value() {
         for (Byte id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Byte id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Byte.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Byte id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Byte.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_ascii_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Byte[] id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Byte[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Byte[] id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Byte[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/ByteValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/ByteValueArrayTest.java
index 4cd059f9a..e157264a1 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/ByteValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/ByteValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -13,7 +13,7 @@ import static junit.framework.TestCase.assertNull;
 public class ByteValueArrayTest {
     @Test
     public void test_parse_null() {
-        byte[] bytes = JSON.parseObject("null", byte[].class);
+        byte[] bytes = JsonMapper.parseJsonObject("null", byte[].class);
         assertNull(bytes);
     }
 
@@ -25,7 +25,7 @@ public class ByteValueArrayTest {
 
     @Test
     public void test_parse() {
-        byte[] bytes = JSON.parseObject("[101,102]", byte[].class);
+        byte[] bytes = JsonMapper.parseJsonObject("[101,102]", byte[].class);
         assertEquals(2, bytes.length);
         assertEquals(101, bytes[0]);
         assertEquals(102, bytes[1]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/Calendar1Test.java b/core/src/test/java/com/alibaba/fastjson2/primitves/Calendar1Test.java
index 00f63a536..8ada8885e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/Calendar1Test.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/Calendar1Test.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.writer.*;
@@ -110,33 +110,33 @@ public class Calendar1Test {
     @Test
     public void test_utf16_0() {
         assertEquals(6
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017년7월3일\""
                         , Calendar.class
                 ).get(Calendar.MONTH));
         assertEquals(6
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017년7월13일\""
                         , Calendar.class
                 ).get(Calendar.MONTH));
 
         assertEquals(6
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017-7-13\""
                         , Calendar.class
                 ).get(Calendar.MONTH));
         assertEquals(11
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017-12-7\""
                         , Calendar.class
                 ).get(Calendar.MONTH));
         assertEquals(11
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017-12-17\""
                         , Calendar.class
                 ).get(Calendar.MONTH));
         assertEquals(11
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017年12月17日\""
                         , Calendar.class
                 ).get(Calendar.MONTH));
@@ -145,43 +145,43 @@ public class Calendar1Test {
     @Test
     public void test_utf8_0() {
         assertEquals(2017
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"20171213\""
                                 .getBytes(StandardCharsets.UTF_8)
                         , Calendar.class
                 ).get(Calendar.YEAR));
         assertEquals(2017
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017-2-3\""
                                 .getBytes(StandardCharsets.UTF_8)
                         , Calendar.class
                 ).get(Calendar.YEAR));
         assertEquals(11
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017-12-3\""
                                 .getBytes(StandardCharsets.UTF_8)
                         , Calendar.class
                 ).get(Calendar.MONTH));
         assertEquals(2
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017-3-13\""
                                 .getBytes(StandardCharsets.UTF_8)
                         , Calendar.class
                 ).get(Calendar.MONTH));
         assertEquals(2017
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017年1月13日\""
                                 .getBytes(StandardCharsets.UTF_8)
                                 , Calendar.class
                         ).get(Calendar.YEAR));
         assertEquals(11
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017年12月13日\""
                                 .getBytes(StandardCharsets.UTF_8)
                         , Calendar.class
                 ).get(Calendar.MONTH));
         assertEquals(2017
-                , JSON.parseObject(
+                , JsonMapper.parseJsonObject(
                         "\"2017年11月9日\""
                                 .getBytes(StandardCharsets.UTF_8)
                         , Calendar.class
@@ -329,9 +329,9 @@ public class Calendar1Test {
         for (Calendar id : dates) {
             Calendar1 vo = new Calendar1();
             vo.setDate(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Calendar1 v1 = JSON.parseObject(str, Calendar1.class);
+            Calendar1 v1 = JsonMapper.parseJsonObject(str, Calendar1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -340,8 +340,8 @@ public class Calendar1Test {
     public void test_str_value() {
         for (int i = 0; i < dates.length; i++) {
             Calendar id = dates[i];
-            String str = JSON.toJSONString(id);
-            Calendar id2 = JSON.parseObject(str, Calendar.class);
+            String str = JsonMapper.toJsonString(id);
+            Calendar id2 = JsonMapper.parseJsonObject(str, Calendar.class);
             assertEquals(str, id, id2);
         }
     }
@@ -356,8 +356,8 @@ public class Calendar1Test {
             }
             primitiveValues[i] = dates[i].getTimeInMillis();
         }
-        String str = JSON.toJSONString(primitiveValues);
-        long[] id2 = JSON.parseObject(str, long[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        long[] id2 = JsonMapper.parseJsonObject(str, long[].class);
         assertEquals(dates.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -371,9 +371,9 @@ public class Calendar1Test {
 
             Calendar1 vo = new Calendar1();
             vo.setDate(id);
-            byte[] utf8 = JSON.toJSONBytes(vo);
+            byte[] utf8 = JsonMapper.toJsonBytes(vo);
 
-            Calendar1 v1 = JSON.parseObject(utf8, Calendar1.class);
+            Calendar1 v1 = JsonMapper.parseJsonObject(utf8, Calendar1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -382,8 +382,8 @@ public class Calendar1Test {
     public void test_utf8_value() {
         for (int i = 0; i < dates.length; i++) {
             Calendar id = dates[i];
-            byte[] utf8 = JSON.toJSONBytes(id);
-            Calendar id2 = JSON.parseObject(utf8, Calendar.class);
+            byte[] utf8 = JsonMapper.toJsonBytes(id);
+            Calendar id2 = JsonMapper.parseJsonObject(utf8, Calendar.class);
             assertEquals(id, id2);
         }
     }
@@ -395,8 +395,8 @@ public class Calendar1Test {
             if (id == null) {
                 continue;
             }
-            byte[] utf8 = JSON.toJSONBytes(new Date(id.getTimeInMillis()));
-            Calendar id2 = JSON.parseObject(utf8, Calendar.class);
+            byte[] utf8 = JsonMapper.toJsonBytes(new Date(id.getTimeInMillis()));
+            Calendar id2 = JsonMapper.parseJsonObject(utf8, Calendar.class);
             assertEquals(id, id2);
         }
     }
@@ -408,8 +408,8 @@ public class Calendar1Test {
             if (id == null) {
                 continue;
             }
-            byte[] utf8 = JSON.toJSONBytes(id.getTimeInMillis());
-            Calendar id2 = JSON.parseObject(utf8, Calendar.class);
+            byte[] utf8 = JsonMapper.toJsonBytes(id.getTimeInMillis());
+            Calendar id2 = JsonMapper.parseJsonObject(utf8, Calendar.class);
             assertEquals(id, id2);
         }
     }
@@ -424,8 +424,8 @@ public class Calendar1Test {
             }
             primitiveValues[i] = dates[i].getTimeInMillis();
         }
-        byte[] utf8 = JSON.toJSONBytes(primitiveValues);
-        Calendar[] id2 = JSON.parseObject(utf8, Calendar[].class);
+        byte[] utf8 = JsonMapper.toJsonBytes(primitiveValues);
+        Calendar[] id2 = JsonMapper.parseJsonObject(utf8, Calendar[].class);
         assertEquals(dates.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i].getTimeInMillis());
@@ -442,8 +442,8 @@ public class Calendar1Test {
             }
             primitiveValues[i] = dates[i].getTimeInMillis();
         }
-        byte[] utf8 = JSON.toJSONBytes(primitiveValues);
-        long[] id2 = JSON.parseObject(utf8, long[].class);
+        byte[] utf8 = JsonMapper.toJsonBytes(primitiveValues);
+        long[] id2 = JsonMapper.parseJsonObject(utf8, long[].class);
         assertEquals(dates.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -457,9 +457,9 @@ public class Calendar1Test {
 
             Calendar1 vo = new Calendar1();
             vo.setDate(id);
-            byte[] utf8 = JSON.toJSONBytes(vo);
+            byte[] utf8 = JsonMapper.toJsonBytes(vo);
 
-            Calendar1 v1 = JSON.parseObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, Calendar1.class);
+            Calendar1 v1 = JsonMapper.parseJsonObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, Calendar1.class);
             if (id == null) {
                 assertNull(v1.getDate());
                 continue;
@@ -472,8 +472,8 @@ public class Calendar1Test {
     public void test_ascii_value() {
         for (int i = 0; i < dates.length; i++) {
             Calendar id = dates[i];
-            byte[] utf8 = JSON.toJSONBytes(id);
-            Calendar id2 = JSON.parseObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, Calendar.class);
+            byte[] utf8 = JsonMapper.toJsonBytes(id);
+            Calendar id2 = JsonMapper.parseJsonObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, Calendar.class);
             assertEquals(id, id2);
         }
     }
@@ -488,8 +488,8 @@ public class Calendar1Test {
             }
             primitiveValues[i] = dates[i].getTimeInMillis();
         }
-        byte[] utf8 = JSON.toJSONBytes(primitiveValues);
-        long[] id2 = JSON.parseObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, long[].class);
+        byte[] utf8 = JsonMapper.toJsonBytes(primitiveValues);
+        long[] id2 = JsonMapper.parseJsonObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, long[].class);
         assertEquals(dates.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/CharValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/CharValueArrayTest.java
index 9b10629c3..f6e336fa0 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/CharValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/CharValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -15,7 +15,7 @@ import static junit.framework.TestCase.assertNull;
 public class CharValueArrayTest {
     @Test
     public void test_parse_null() {
-        char[] bytes = JSON.parseObject("null", char[].class);
+        char[] bytes = JsonMapper.parseJsonObject("null", char[].class);
         assertNull(bytes);
     }
 
@@ -36,7 +36,7 @@ public class CharValueArrayTest {
 
     @Test
     public void test_parse() {
-        char[] chars = JSON.parseObject("[101,102]", char[].class);
+        char[] chars = JsonMapper.parseJsonObject("[101,102]", char[].class);
         assertEquals(2, chars.length);
         assertEquals(101, chars[0]);
         assertEquals(102, chars[1]);
@@ -44,7 +44,7 @@ public class CharValueArrayTest {
 
     @Test
     public void test_parse_str() {
-        char[] chars = JSON.parseObject("[\"A\"]", char[].class);
+        char[] chars = JsonMapper.parseJsonObject("[\"A\"]", char[].class);
         assertEquals(1, chars.length);
         assertEquals('A', chars[0]);
     }
@@ -60,20 +60,20 @@ public class CharValueArrayTest {
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
     }
 
     @Test
     public void test_writeNull2() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO2()));
+                , JsonMapper.toJsonString(new VO2()));
 
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
     }
 
     public static class VO {
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/CurrencyTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/CurrencyTest.java
index bda2459c4..5fa9f2fb6 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/CurrencyTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/CurrencyTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -14,10 +14,10 @@ public class CurrencyTest {
         VO vo = new VO();
         vo.value = Currency.getInstance("CNY");
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"value\":\"CNY\"}", str);
 
-        VO v2 = JSON.parseObject(str, VO.class);
+        VO v2 = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(vo.value, v2.value);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/Date1Test.java b/core/src/test/java/com/alibaba/fastjson2/primitves/Date1Test.java
index 0949ec3be..941eea681 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/Date1Test.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/Date1Test.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -337,9 +337,9 @@ public class Date1Test {
         for (Date id : dates) {
             Date1 vo = new Date1();
             vo.setDate(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Date1 v1 = JSON.parseObject(str, Date1.class);
+            Date1 v1 = JsonMapper.parseJsonObject(str, Date1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -348,8 +348,8 @@ public class Date1Test {
     public void test_str_value() {
         for (int i = 0; i < dates.length; i++) {
             Date id = dates[i];
-            String str = JSON.toJSONString(id);
-            Date id2 = JSON.parseObject(str, Date.class);
+            String str = JsonMapper.toJsonString(id);
+            Date id2 = JsonMapper.parseJsonObject(str, Date.class);
             assertEquals(str, id, id2);
         }
     }
@@ -364,8 +364,8 @@ public class Date1Test {
             }
             primitiveValues[i] = dates[i].getTime();
         }
-        String str = JSON.toJSONString(primitiveValues);
-        long[] id2 = JSON.parseObject(str, long[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        long[] id2 = JsonMapper.parseJsonObject(str, long[].class);
         assertEquals(dates.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -379,9 +379,9 @@ public class Date1Test {
 
             Date1 vo = new Date1();
             vo.setDate(id);
-            byte[] utf8 = JSON.toJSONBytes(vo);
+            byte[] utf8 = JsonMapper.toJsonBytes(vo);
 
-            Date1 v1 = JSON.parseObject(utf8, Date1.class);
+            Date1 v1 = JsonMapper.parseJsonObject(utf8, Date1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -390,8 +390,8 @@ public class Date1Test {
     public void test_utf8_value() {
         for (int i = 0; i < dates.length; i++) {
             Date id = dates[i];
-            byte[] utf8 = JSON.toJSONBytes(id);
-            Date id2 = JSON.parseObject(utf8, Date.class);
+            byte[] utf8 = JsonMapper.toJsonBytes(id);
+            Date id2 = JsonMapper.parseJsonObject(utf8, Date.class);
             assertEquals(id, id2);
         }
     }
@@ -403,8 +403,8 @@ public class Date1Test {
             if (id == null) {
                 continue;
             }
-            byte[] utf8 = JSON.toJSONBytes(id.getTime());
-            Date id2 = JSON.parseObject(utf8, Date.class);
+            byte[] utf8 = JsonMapper.toJsonBytes(id.getTime());
+            Date id2 = JsonMapper.parseJsonObject(utf8, Date.class);
             assertEquals(id, id2);
         }
     }
@@ -419,8 +419,8 @@ public class Date1Test {
             }
             primitiveValues[i] = dates[i].getTime();
         }
-        byte[] utf8 = JSON.toJSONBytes(primitiveValues);
-        Date[] id2 = JSON.parseObject(utf8, Date[].class);
+        byte[] utf8 = JsonMapper.toJsonBytes(primitiveValues);
+        Date[] id2 = JsonMapper.parseJsonObject(utf8, Date[].class);
         assertEquals(dates.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i].getTime());
@@ -437,8 +437,8 @@ public class Date1Test {
             }
             primitiveValues[i] = dates[i].getTime();
         }
-        byte[] utf8 = JSON.toJSONBytes(primitiveValues);
-        long[] id2 = JSON.parseObject(utf8, long[].class);
+        byte[] utf8 = JsonMapper.toJsonBytes(primitiveValues);
+        long[] id2 = JsonMapper.parseJsonObject(utf8, long[].class);
         assertEquals(dates.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -452,9 +452,9 @@ public class Date1Test {
 
             Date1 vo = new Date1();
             vo.setDate(id);
-            byte[] utf8 = JSON.toJSONBytes(vo);
+            byte[] utf8 = JsonMapper.toJsonBytes(vo);
 
-            Date1 v1 = JSON.parseObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, Date1.class);
+            Date1 v1 = JsonMapper.parseJsonObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, Date1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -463,8 +463,8 @@ public class Date1Test {
     public void test_ascii_value() {
         for (int i = 0; i < dates.length; i++) {
             Date id = dates[i];
-            byte[] utf8 = JSON.toJSONBytes(id);
-            Date id2 = JSON.parseObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, Date.class);
+            byte[] utf8 = JsonMapper.toJsonBytes(id);
+            Date id2 = JsonMapper.parseJsonObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, Date.class);
             assertEquals(id, id2);
         }
     }
@@ -479,8 +479,8 @@ public class Date1Test {
             }
             primitiveValues[i] = dates[i].getTime();
         }
-        byte[] utf8 = JSON.toJSONBytes(primitiveValues);
-        long[] id2 = JSON.parseObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, long[].class);
+        byte[] utf8 = JsonMapper.toJsonBytes(primitiveValues);
+        long[] id2 = JsonMapper.parseJsonObject(utf8, 0, utf8.length, StandardCharsets.US_ASCII, long[].class);
         assertEquals(dates.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -494,7 +494,7 @@ public class Date1Test {
 
             Date1 vo = new Date1();
             vo.setDate(id);
-            byte[] utf8 = JSON.toJSONBytes(vo);
+            byte[] utf8 = JsonMapper.toJsonBytes(vo);
 
             ByteArrayInputStream byteIn = new ByteArrayInputStream(utf8);
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/DecimalTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/DecimalTest.java
index e6146ad0a..d7d045f0c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/DecimalTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/DecimalTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.writer.ObjectWriter;
 import com.alibaba.fastjson2.writer.ObjectWriterCreator;
@@ -69,7 +69,7 @@ public class DecimalTest {
     public void test_null_str() {
         BigDecimal decimal = null;
         assertEquals("null"
-                , JSON.toJSONString(decimal));
+                , JsonMapper.toJsonString(decimal));
     }
 
     @Test
@@ -77,14 +77,14 @@ public class DecimalTest {
         BigDecimal decimal = null;
         assertEquals("null"
                 , new String(
-                        JSON.toJSONBytes(decimal)));
+                        JsonMapper.toJsonBytes(decimal)));
     }
 
     @Test
     public void test_BrowserCompatible_str() {
         BigDecimal decimal = new BigDecimal("90071992547409910");
         assertEquals("\"90071992547409910\""
-                , JSON.toJSONString(decimal, JSONWriter.Feature.BrowserCompatible));
+                , JsonMapper.toJsonString(decimal, JSONWriter.Feature.BrowserCompatible));
     }
 
     @Test
@@ -92,7 +92,7 @@ public class DecimalTest {
         BigDecimal decimal = new BigDecimal("90071992547409910");
         assertEquals("\"90071992547409910\""
                 , new String(
-                        JSON.toJSONBytes(decimal, JSONWriter.Feature.BrowserCompatible)));
+                        JsonMapper.toJsonBytes(decimal, JSONWriter.Feature.BrowserCompatible)));
     }
 
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleTest.java
index 1cbe0c6d2..e2bb885ac 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2_vo.Double1;
@@ -167,9 +167,9 @@ public class DoubleTest {
         for (Double id : values) {
             Double1 vo = new Double1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Double1 v1 = JSON.parseObject(utf8Bytes, Double1.class);
+            Double1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Double1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -177,16 +177,16 @@ public class DoubleTest {
     @Test
     public void test_utf8_value() {
         for (Double id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Double id2 = JSON.parseObject(utf8Bytes, Double.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Double id2 = JsonMapper.parseJsonObject(utf8Bytes, Double.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_utf8_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Double[] id2 = JSON.parseObject(utf8Bytes, Double[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Double[] id2 = JsonMapper.parseJsonObject(utf8Bytes, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -198,9 +198,9 @@ public class DoubleTest {
         for (Double id : values) {
             Double1 vo = new Double1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Double1 v1 = JSON.parseObject(str, Double1.class);
+            Double1 v1 = JsonMapper.parseJsonObject(str, Double1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -208,8 +208,8 @@ public class DoubleTest {
     @Test
     public void test_str_value() {
         for (Double id : values) {
-            String str = JSON.toJSONString(id);
-            Double id2 = JSON.parseObject(str, Double.class);
+            String str = JsonMapper.toJsonString(id);
+            Double id2 = JsonMapper.parseJsonObject(str, Double.class);
             assertEquals(id, id2);
         }
     }
@@ -224,8 +224,8 @@ public class DoubleTest {
             }
             primitiveValues[i] = values[i];
         }
-        String str = JSON.toJSONString(primitiveValues);
-        double[] id2 = JSON.parseObject(str, double[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        double[] id2 = JsonMapper.parseJsonObject(str, double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -242,8 +242,8 @@ public class DoubleTest {
             }
             primitiveValues[i] = values[i];
         }
-        String str = JSON.toJSONString(primitiveValues);
-        Double[] id2 = JSON.parseObject(str, Double[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        Double[] id2 = JsonMapper.parseJsonObject(str, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -252,8 +252,8 @@ public class DoubleTest {
 
     @Test
     public void test_str_array() {
-        String str = JSON.toJSONString(values);
-        Double[] id2 = JSON.parseObject(str, Double[].class);
+        String str = JsonMapper.toJsonString(values);
+        Double[] id2 = JsonMapper.parseJsonObject(str, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -265,9 +265,9 @@ public class DoubleTest {
         for (Double id : values) {
             Double1 vo = new Double1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Double1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double1.class);
+            Double1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -275,16 +275,16 @@ public class DoubleTest {
     @Test
     public void test_ascii_value() {
         for (Double id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Double id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Double id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_ascii_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Double[] id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Double[] id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueArrayTest.java
index 82e60fcbb..4b6f48dc8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -14,7 +14,7 @@ import static junit.framework.TestCase.assertNull;
 public class DoubleValueArrayTest {
     @Test
     public void test_parse_null() {
-        double[] values = JSON.parseObject("null", double[].class);
+        double[] values = JsonMapper.parseJsonObject("null", double[].class);
         assertNull(values);
     }
 
@@ -26,7 +26,7 @@ public class DoubleValueArrayTest {
 
     @Test
     public void test_parse() {
-        double[] bytes = JSON.parseObject("[101,102]", double[].class);
+        double[] bytes = JsonMapper.parseJsonObject("[101,102]", double[].class);
         assertEquals(2, bytes.length);
         assertEquals(101D, bytes[0]);
         assertEquals(102D, bytes[1]);
@@ -44,28 +44,28 @@ public class DoubleValueArrayTest {
     @Test
     public void test_writeNotNull() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO()));
+                , JsonMapper.toJsonString(new VO()));
         assertEquals("{}",
                 new String(
-                        JSON.toJSONBytes(new VO())));
+                        JsonMapper.toJsonBytes(new VO())));
     }
 
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
     }
 
     @Test
     public void test_writeNull2() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO2(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO2(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
     }
 
     public static class VO {
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueFieldTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueFieldTest.java
index 5826a9be4..011b47aea 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueFieldTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueFieldTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2.JSONWriter;
@@ -206,9 +206,9 @@ public class DoubleValueFieldTest {
             }
             DoubleValueField1 vo = new DoubleValueField1();
             vo.v0000 = id;
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            DoubleValueField1 v1 = JSON.parseObject(utf8Bytes, DoubleValueField1.class);
+            DoubleValueField1 v1 = JsonMapper.parseJsonObject(utf8Bytes, DoubleValueField1.class);
             assertEquals(vo.v0000, v1.v0000);
         }
     }
@@ -216,23 +216,23 @@ public class DoubleValueFieldTest {
     @Test
     public void test_utf8_null() {
         byte[] utf8 = "{\"v0000\":null}".getBytes(StandardCharsets.UTF_8);
-        DoubleValueField1 v1 = JSON.parseObject(utf8, DoubleValueField1.class);
+        DoubleValueField1 v1 = JsonMapper.parseJsonObject(utf8, DoubleValueField1.class);
         assertEquals(0D, v1.v0000);
     }
 
     @Test
     public void test_utf8_value() {
         for (Double id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Double id2 = JSON.parseObject(utf8Bytes, Double.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Double id2 = JsonMapper.parseJsonObject(utf8Bytes, Double.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_utf8_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Double[] id2 = JSON.parseObject(utf8Bytes, Double[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Double[] id2 = JsonMapper.parseJsonObject(utf8Bytes, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -248,9 +248,9 @@ public class DoubleValueFieldTest {
 
             DoubleValueField1 vo = new DoubleValueField1();
             vo.v0000 = id;
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            DoubleValueField1 v1 = JSON.parseObject(str, DoubleValueField1.class);
+            DoubleValueField1 v1 = JsonMapper.parseJsonObject(str, DoubleValueField1.class);
             assertEquals(vo.v0000, v1.v0000);
         }
     }
@@ -258,15 +258,15 @@ public class DoubleValueFieldTest {
     @Test
     public void test_str_value() {
         for (Double id : values) {
-            String str = JSON.toJSONString(id);
-            Double id2 = JSON.parseObject(str, Double.class);
+            String str = JsonMapper.toJsonString(id);
+            Double id2 = JsonMapper.parseJsonObject(str, Double.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_str_null() {
-        DoubleValueField1 v1 = JSON.parseObject("{\"v0000\":null}", DoubleValueField1.class);
+        DoubleValueField1 v1 = JsonMapper.parseJsonObject("{\"v0000\":null}", DoubleValueField1.class);
         assertEquals(0D, v1.v0000);
     }
 
@@ -279,8 +279,8 @@ public class DoubleValueFieldTest {
             }
             primitiveValues[i] = values[i];
         }
-        String str = JSON.toJSONString(primitiveValues);
-        Double[] id2 = JSON.parseObject(str, Double[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        Double[] id2 = JsonMapper.parseJsonObject(str, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -289,8 +289,8 @@ public class DoubleValueFieldTest {
 
     @Test
     public void test_str_array() {
-        String str = JSON.toJSONString(values);
-        Double[] id2 = JSON.parseObject(str, Double[].class);
+        String str = JsonMapper.toJsonString(values);
+        Double[] id2 = JsonMapper.parseJsonObject(str, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -306,9 +306,9 @@ public class DoubleValueFieldTest {
 
             DoubleValueField1 vo = new DoubleValueField1();
             vo.v0000 = id;
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            DoubleValueField1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, DoubleValueField1.class);
+            DoubleValueField1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, DoubleValueField1.class);
             assertEquals(vo.v0000, v1.v0000);
         }
     }
@@ -316,23 +316,23 @@ public class DoubleValueFieldTest {
     @Test
     public void test_ascii_null() {
         byte[] utf8Bytes = "{\"v0000\":null}".getBytes(StandardCharsets.UTF_8);
-        DoubleValueField1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, DoubleValueField1.class);
+        DoubleValueField1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, DoubleValueField1.class);
         assertEquals(0D, v1.v0000);
     }
 
     @Test
     public void test_ascii_value() {
         for (Double id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Double id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Double id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_ascii_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Double[] id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Double[] id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueTest.java
index bcadaf9c6..e14a05a19 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/DoubleValueTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2.JSONWriter;
@@ -206,9 +206,9 @@ public class DoubleValueTest {
             }
             DoubleValue1 vo = new DoubleValue1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            DoubleValue1 v1 = JSON.parseObject(utf8Bytes, DoubleValue1.class);
+            DoubleValue1 v1 = JsonMapper.parseJsonObject(utf8Bytes, DoubleValue1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -216,23 +216,23 @@ public class DoubleValueTest {
     @Test
     public void test_utf8_null() {
         byte[] utf8 = "{\"v0000\":null}".getBytes(StandardCharsets.UTF_8);
-        DoubleValue1 v1 = JSON.parseObject(utf8, DoubleValue1.class);
+        DoubleValue1 v1 = JsonMapper.parseJsonObject(utf8, DoubleValue1.class);
         assertEquals(0D, v1.getV0000());
     }
 
     @Test
     public void test_utf8_value() {
         for (Double id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Double id2 = JSON.parseObject(utf8Bytes, Double.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Double id2 = JsonMapper.parseJsonObject(utf8Bytes, Double.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_utf8_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Double[] id2 = JSON.parseObject(utf8Bytes, Double[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Double[] id2 = JsonMapper.parseJsonObject(utf8Bytes, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -248,9 +248,9 @@ public class DoubleValueTest {
 
             DoubleValue1 vo = new DoubleValue1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            DoubleValue1 v1 = JSON.parseObject(str, DoubleValue1.class);
+            DoubleValue1 v1 = JsonMapper.parseJsonObject(str, DoubleValue1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -258,15 +258,15 @@ public class DoubleValueTest {
     @Test
     public void test_str_value() {
         for (Double id : values) {
-            String str = JSON.toJSONString(id);
-            Double id2 = JSON.parseObject(str, Double.class);
+            String str = JsonMapper.toJsonString(id);
+            Double id2 = JsonMapper.parseJsonObject(str, Double.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_str_null() {
-        DoubleValue1 v1 = JSON.parseObject("{\"v0000\":null}", DoubleValue1.class);
+        DoubleValue1 v1 = JsonMapper.parseJsonObject("{\"v0000\":null}", DoubleValue1.class);
         assertEquals(0D, v1.getV0000());
     }
 
@@ -279,8 +279,8 @@ public class DoubleValueTest {
             }
             primitiveValues[i] = values[i];
         }
-        String str = JSON.toJSONString(primitiveValues);
-        Double[] id2 = JSON.parseObject(str, Double[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        Double[] id2 = JsonMapper.parseJsonObject(str, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -289,8 +289,8 @@ public class DoubleValueTest {
 
     @Test
     public void test_str_array() {
-        String str = JSON.toJSONString(values);
-        Double[] id2 = JSON.parseObject(str, Double[].class);
+        String str = JsonMapper.toJsonString(values);
+        Double[] id2 = JsonMapper.parseJsonObject(str, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -306,9 +306,9 @@ public class DoubleValueTest {
 
             DoubleValue1 vo = new DoubleValue1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            DoubleValue1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, DoubleValue1.class);
+            DoubleValue1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, DoubleValue1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -316,23 +316,23 @@ public class DoubleValueTest {
     @Test
     public void test_ascii_null() {
         byte[] utf8Bytes = "{\"v0000\":null}".getBytes(StandardCharsets.UTF_8);
-        DoubleValue1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, DoubleValue1.class);
+        DoubleValue1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, DoubleValue1.class);
         assertEquals(0D, v1.getV0000());
     }
 
     @Test
     public void test_ascii_value() {
         for (Double id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Double id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Double id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_ascii_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Double[] id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Double[] id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Double[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/Enum_0.java b/core/src/test/java/com/alibaba/fastjson2/primitves/Enum_0.java
index e6ee35205..e115210d4 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/Enum_0.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/Enum_0.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -363,9 +363,9 @@ public class Enum_0 {
         for (Type id : types) {
             VO vo = new VO();
             vo.setValue(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            VO v1 = JSON.parseObject(str, VO.class);
+            VO v1 = JsonMapper.parseJsonObject(str, VO.class);
             assertEquals(vo.getValue(), v1.getValue());
         }
     }
@@ -373,8 +373,8 @@ public class Enum_0 {
     @Test
     public void test_str_value() {
         for (Type id : types) {
-            String str = JSON.toJSONString(id);
-            Type id2 = JSON.parseObject(str, Type.class);
+            String str = JsonMapper.toJsonString(id);
+            Type id2 = JsonMapper.parseJsonObject(str, Type.class);
             assertEquals(id, id2);
         }
     }
@@ -382,8 +382,8 @@ public class Enum_0 {
     @Test
     public void test_str_ordinal_value() {
         for (Type id : types) {
-            String str = JSON.toJSONString(id.ordinal());
-            Type id2 = JSON.parseObject(str, Type.class);
+            String str = JsonMapper.toJsonString(id.ordinal());
+            Type id2 = JsonMapper.parseJsonObject(str, Type.class);
             assertEquals(id, id2);
         }
     }
@@ -393,9 +393,9 @@ public class Enum_0 {
         for (Type id : types) {
             VO vo = new VO();
             vo.setValue(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            VO v1 = JSON.parseObject(utf8Bytes, VO.class);
+            VO v1 = JsonMapper.parseJsonObject(utf8Bytes, VO.class);
             assertEquals(vo.getValue(), v1.getValue());
         }
     }
@@ -403,8 +403,8 @@ public class Enum_0 {
     @Test
     public void test_utf8_value() {
         for (Type id : types) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Type id2 = JSON.parseObject(utf8Bytes, Type.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Type id2 = JsonMapper.parseJsonObject(utf8Bytes, Type.class);
             assertEquals(id, id2);
         }
     }
@@ -412,8 +412,8 @@ public class Enum_0 {
     @Test
     public void test_utf8_orinal_value() {
         for (Type id : types) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id.ordinal());
-            Type id2 = JSON.parseObject(utf8Bytes, Type.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id.ordinal());
+            Type id2 = JsonMapper.parseJsonObject(utf8Bytes, Type.class);
             assertEquals(id, id2);
         }
     }
@@ -423,9 +423,9 @@ public class Enum_0 {
         for (Type id : types) {
             VO vo = new VO();
             vo.setValue(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            VO v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, VO.class);
+            VO v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, VO.class);
             assertEquals(vo.getValue(), v1.getValue());
         }
     }
@@ -436,8 +436,8 @@ public class Enum_0 {
             if (id == Type.十1) {
                 continue;
             }
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Type id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Type.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Type id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Type.class);
             assertEquals(id, id2);
         }
     }
@@ -445,8 +445,8 @@ public class Enum_0 {
     @Test
     public void test_ascii_ordinal_value() {
         for (Type id : types) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id.ordinal());
-            Type id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Type.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id.ordinal());
+            Type id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Type.class);
             assertEquals(id, id2);
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/FloatTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/FloatTest.java
index 034e5440a..ffb5d2084 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/FloatTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/FloatTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2_vo.Float1;
@@ -164,9 +164,9 @@ public class FloatTest {
         for (Float id : values) {
             Float1 vo = new Float1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Float1 v1 = JSON.parseObject(utf8Bytes, Float1.class);
+            Float1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Float1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -174,16 +174,16 @@ public class FloatTest {
     @Test
     public void test_utf8_value() {
         for (Float id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Float id2 = JSON.parseObject(utf8Bytes, Float.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Float id2 = JsonMapper.parseJsonObject(utf8Bytes, Float.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_utf8_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Float[] id2 = JSON.parseObject(utf8Bytes, Float[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Float[] id2 = JsonMapper.parseJsonObject(utf8Bytes, Float[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -195,9 +195,9 @@ public class FloatTest {
         for (Float id : values) {
             Float1 vo = new Float1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Float1 v1 = JSON.parseObject(str, Float1.class);
+            Float1 v1 = JsonMapper.parseJsonObject(str, Float1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -205,8 +205,8 @@ public class FloatTest {
     @Test
     public void test_str_value() {
         for (Float id : values) {
-            String str = JSON.toJSONString(id);
-            Float id2 = JSON.parseObject(str, Float.class);
+            String str = JsonMapper.toJsonString(id);
+            Float id2 = JsonMapper.parseJsonObject(str, Float.class);
             assertEquals(id, id2);
         }
     }
@@ -221,8 +221,8 @@ public class FloatTest {
             }
             primitiveValues[i] = values[i];
         }
-        String str = JSON.toJSONString(primitiveValues);
-        float[] id2 = JSON.parseObject(str, float[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        float[] id2 = JsonMapper.parseJsonObject(str, float[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -231,8 +231,8 @@ public class FloatTest {
 
     @Test
     public void test_str_array() {
-        String str = JSON.toJSONString(values);
-        Float[] id2 = JSON.parseObject(str, Float[].class);
+        String str = JsonMapper.toJsonString(values);
+        Float[] id2 = JsonMapper.parseJsonObject(str, Float[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -244,9 +244,9 @@ public class FloatTest {
         for (Float id : values) {
             Float1 vo = new Float1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Float1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float1.class);
+            Float1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -254,16 +254,16 @@ public class FloatTest {
     @Test
     public void test_ascii_value() {
         for (Float id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Float id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Float id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_ascii_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Float[] id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Float[] id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/FloatValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/FloatValueArrayTest.java
index 14c31a924..befa79b1d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/FloatValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/FloatValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -14,7 +14,7 @@ import static junit.framework.TestCase.assertNull;
 public class FloatValueArrayTest {
     @Test
     public void test_parse_null() {
-        float[] values = JSON.parseObject("null", float[].class);
+        float[] values = JsonMapper.parseJsonObject("null", float[].class);
         assertNull(values);
     }
 
@@ -26,7 +26,7 @@ public class FloatValueArrayTest {
 
     @Test
     public void test_parse() {
-        float[] bytes = JSON.parseObject("[101,102]", float[].class);
+        float[] bytes = JsonMapper.parseJsonObject("[101,102]", float[].class);
         assertEquals(2, bytes.length);
         assertEquals(101F, bytes[0]);
         assertEquals(102F, bytes[1]);
@@ -44,20 +44,20 @@ public class FloatValueArrayTest {
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
     }
 
     @Test
     public void test_writeNull2() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO2()));
+                , JsonMapper.toJsonString(new VO2()));
 
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
     }
 
     public static class VO {
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/FloatValueTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/FloatValueTest.java
index 3e7f269c3..0c0912a50 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/FloatValueTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/FloatValueTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2.JSONWriter;
@@ -193,9 +193,9 @@ public class FloatValueTest {
         for (Float id : values) {
             FloatValue1 vo = new FloatValue1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            FloatValue1 v1 = JSON.parseObject(utf8Bytes, FloatValue1.class);
+            FloatValue1 v1 = JsonMapper.parseJsonObject(utf8Bytes, FloatValue1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -203,23 +203,23 @@ public class FloatValueTest {
     @Test
     public void test_utf8_null() {
         byte[] utf8Bytes = "{\"v0000\":null}".getBytes(StandardCharsets.UTF_8);
-        FloatValue1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.UTF_8, FloatValue1.class);
+        FloatValue1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.UTF_8, FloatValue1.class);
         assertEquals(0F, v1.getV0000());
     }
 
     @Test
     public void test_utf8_value() {
         for (Float id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Float id2 = JSON.parseObject(utf8Bytes, Float.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Float id2 = JsonMapper.parseJsonObject(utf8Bytes, Float.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_utf8_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Float[] id2 = JSON.parseObject(utf8Bytes, Float[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Float[] id2 = JsonMapper.parseJsonObject(utf8Bytes, Float[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -231,9 +231,9 @@ public class FloatValueTest {
         for (Float id : values) {
             FloatValue1 vo = new FloatValue1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            FloatValue1 v1 = JSON.parseObject(str, FloatValue1.class);
+            FloatValue1 v1 = JsonMapper.parseJsonObject(str, FloatValue1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -241,15 +241,15 @@ public class FloatValueTest {
     @Test
     public void test_str_null() {
         String str = "{\"v0000\":null}";
-        FloatValue1 v1 = JSON.parseObject(str, FloatValue1.class);
+        FloatValue1 v1 = JsonMapper.parseJsonObject(str, FloatValue1.class);
         assertEquals(0F, v1.getV0000());
     }
 
     @Test
     public void test_str_value() {
         for (Float id : values) {
-            String str = JSON.toJSONString(id);
-            Float id2 = JSON.parseObject(str, Float.class);
+            String str = JsonMapper.toJsonString(id);
+            Float id2 = JsonMapper.parseJsonObject(str, Float.class);
             assertEquals(id, id2);
         }
     }
@@ -260,8 +260,8 @@ public class FloatValueTest {
         for (int i = 0; i < values.length; i++) {
             primitiveValues[i] = values[i];
         }
-        String str = JSON.toJSONString(primitiveValues);
-        float[] id2 = JSON.parseObject(str, float[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        float[] id2 = JsonMapper.parseJsonObject(str, float[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -270,8 +270,8 @@ public class FloatValueTest {
 
     @Test
     public void test_str_array() {
-        String str = JSON.toJSONString(values);
-        Float[] id2 = JSON.parseObject(str, Float[].class);
+        String str = JsonMapper.toJsonString(values);
+        Float[] id2 = JsonMapper.parseJsonObject(str, Float[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -283,9 +283,9 @@ public class FloatValueTest {
         for (Float id : values) {
             FloatValue1 vo = new FloatValue1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            FloatValue1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, FloatValue1.class);
+            FloatValue1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, FloatValue1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -293,23 +293,23 @@ public class FloatValueTest {
     @Test
     public void test_ascii_null() {
         byte[] utf8Bytes = "{\"v0000\":null}".getBytes(StandardCharsets.UTF_8);
-        FloatValue1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, FloatValue1.class);
+        FloatValue1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, FloatValue1.class);
         assertEquals(0F, v1.getV0000());
     }
 
     @Test
     public void test_ascii_value() {
         for (Float id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Float id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Float id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_ascii_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Float[] id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Float[] id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Float[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/InstantTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/InstantTest.java
index cf9ec585e..e7ff9f519 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/InstantTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/InstantTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2_vo.Instant1;
 import org.junit.jupiter.api.Test;
@@ -37,9 +37,9 @@ public class InstantTest {
         for (ZonedDateTime dateTime : dateTimes) {
             Instant1 vo = new Instant1();
             vo.setV0000(dateTime.toInstant());
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Instant1 v1 = JSON.parseObject(utf8Bytes, Instant1.class);
+            Instant1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Instant1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -49,9 +49,9 @@ public class InstantTest {
         for (ZonedDateTime dateTime : dateTimes) {
             Instant1 vo = new Instant1();
             vo.setV0000(dateTime.toInstant());
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Instant1 v1 = JSON.parseObject(str, Instant1.class);
+            Instant1 v1 = JsonMapper.parseJsonObject(str, Instant1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -61,9 +61,9 @@ public class InstantTest {
         for (ZonedDateTime dateTime : dateTimes) {
             Instant1 vo = new Instant1();
             vo.setV0000(dateTime.toInstant());
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Instant1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Instant1.class);
+            Instant1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Instant1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/Int16ValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/Int16ValueArrayTest.java
index c7bf26635..2a34092c4 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/Int16ValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/Int16ValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -11,13 +11,13 @@ public class Int16ValueArrayTest {
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
 
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(new VO(), JSONWriter.Feature.WriteNulls))
                         , JSONWriter.Feature.WriteNulls));
@@ -26,14 +26,14 @@ public class Int16ValueArrayTest {
     @Test
     public void test_writeNull2() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO2()));
+                , JsonMapper.toJsonString(new VO2()));
 
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
 
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(new VO2(), JSONWriter.Feature.WriteNulls))
                         , JSONWriter.Feature.WriteNulls));
@@ -44,10 +44,10 @@ public class Int16ValueArrayTest {
         VO vo = new VO();
         vo.values = new short[] {1, 2, 3};
         assertEquals("{\"values\":[1,2,3]}"
-                , JSON.toJSONString(vo));
+                , JsonMapper.toJsonString(vo));
 
         assertEquals("{\"values\":[1,2,3]}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(vo))));
     }
@@ -57,10 +57,10 @@ public class Int16ValueArrayTest {
         VO2 vo = new VO2();
         vo.values = new short[] {1, 2, 3};
         assertEquals("{\"values\":[1,2,3]}"
-                , JSON.toJSONString(vo));
+                , JsonMapper.toJsonString(vo));
 
         assertEquals("{\"values\":[1,2,3]}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(vo))));
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/Int32ValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/Int32ValueArrayTest.java
index a40611a19..f9c2d5f77 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/Int32ValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/Int32ValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -11,13 +11,13 @@ public class Int32ValueArrayTest {
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
 
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(new VO(), JSONWriter.Feature.WriteNulls))
                         , JSONWriter.Feature.WriteNulls));
@@ -26,24 +26,24 @@ public class Int32ValueArrayTest {
     @Test
     public void test_writeNull2() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO2()));
+                , JsonMapper.toJsonString(new VO2()));
 
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
 
         assertEquals("{\"values\":[]}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue)));
 
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(new VO2(), JSONWriter.Feature.WriteNulls))
                         , JSONWriter.Feature.WriteNulls));
 
         assertEquals("{\"values\":[]}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(new VO2(), JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue))
                         , JSONWriter.Feature.WriteNulls));
@@ -54,10 +54,10 @@ public class Int32ValueArrayTest {
         VO vo = new VO();
         vo.values = new int[] {1, 2, 3};
         assertEquals("{\"values\":[1,2,3]}"
-                , JSON.toJSONString(vo));
+                , JsonMapper.toJsonString(vo));
 
         assertEquals("{\"values\":[1,2,3]}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(vo))));
     }
@@ -67,10 +67,10 @@ public class Int32ValueArrayTest {
         VO2 vo = new VO2();
         vo.values = new int[] {1, 2, 3,123,1234,12345,123456,1234567,12345678,123456789,1234567890};
         assertEquals("{\"values\":[1,2,3,123,1234,12345,123456,1234567,12345678,123456789,1234567890]}"
-                , JSON.toJSONString(vo));
+                , JsonMapper.toJsonString(vo));
 
         assertEquals("{\"values\":[1,2,3,123,1234,12345,123456,1234567,12345678,123456789,1234567890]}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(vo))));
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/Int64ValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/Int64ValueArrayTest.java
index 27f218bd8..7eceb3f98 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/Int64ValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/Int64ValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -11,13 +11,13 @@ public class Int64ValueArrayTest {
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
 
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(new VO(), JSONWriter.Feature.WriteNulls))
                         , JSONWriter.Feature.WriteNulls));
@@ -26,24 +26,24 @@ public class Int64ValueArrayTest {
     @Test
     public void test_writeNull2() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO2()));
+                , JsonMapper.toJsonString(new VO2()));
 
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
 
         assertEquals("{\"values\":[]}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue)));
 
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(new VO2(), JSONWriter.Feature.WriteNulls))
                         , JSONWriter.Feature.WriteNulls));
 
         assertEquals("{\"values\":[]}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(new VO2(), JSONWriter.Feature.WriteNulls, JSONWriter.Feature.NullAsDefaultValue))
                         , JSONWriter.Feature.WriteNulls));
@@ -54,10 +54,10 @@ public class Int64ValueArrayTest {
         VO vo = new VO();
         vo.values = new long[] {1, 2, 3};
         assertEquals("{\"values\":[1,2,3]}"
-                , JSON.toJSONString(vo));
+                , JsonMapper.toJsonString(vo));
 
         assertEquals("{\"values\":[1,2,3]}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(vo))));
     }
@@ -67,10 +67,10 @@ public class Int64ValueArrayTest {
         VO2 vo = new VO2();
         vo.values = new long[] {1, 2, 3,123,1234,12345,123456,1234567,12345678,123456789,1234567890,12345678901L,123456789012L};
         assertEquals("{\"values\":[1,2,3,123,1234,12345,123456,1234567,12345678,123456789,1234567890,12345678901,123456789012]}"
-                , JSON.toJSONString(vo));
+                , JsonMapper.toJsonString(vo));
 
         assertEquals("{\"values\":[1,2,3,123,1234,12345,123456,1234567,12345678,123456789,1234567890,12345678901,123456789012]}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parseObject(
                                 JSONB.toBytes(vo))));
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/Int64_1.java b/core/src/test/java/com/alibaba/fastjson2/primitves/Int64_1.java
index b6e47abe2..dbe4000c5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/Int64_1.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/Int64_1.java
@@ -160,7 +160,7 @@ public class Int64_1 {
     @Test
     public void test_0() throws Exception {
         String str = "{\"value\":\"123\"}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(123L, vo.getValue().longValue());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/Int8ValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/Int8ValueArrayTest.java
index a24c22477..bda256643 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/Int8ValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/Int8ValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -10,20 +10,20 @@ public class Int8ValueArrayTest {
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
     }
 
     @Test
     public void test_writeNull2() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO2()));
+                , JsonMapper.toJsonString(new VO2()));
 
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
     }
 
     public static class VO {
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/IntTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/IntTest.java
index f5dbc6854..0adeed2aa 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/IntTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/IntTest.java
@@ -135,9 +135,9 @@ public class IntTest {
         for (int id : values) {
             Int1 vo = new Int1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Int1 v1 = JSON.parseObject(utf8Bytes, Int1.class);
+            Int1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Int1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -145,8 +145,8 @@ public class IntTest {
     @Test
     public void test_utf8_value() {
         for (int id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            int id2 = JSON.parseObject(utf8Bytes, int.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            int id2 = JsonMapper.parseJsonObject(utf8Bytes, int.class);
             assertEquals(id, id2);
         }
     }
@@ -156,9 +156,9 @@ public class IntTest {
         for (int id : values) {
             Int1 vo = new Int1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Int1 v1 = JSON.parseObject(str, Int1.class);
+            Int1 v1 = JsonMapper.parseJsonObject(str, Int1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -166,8 +166,8 @@ public class IntTest {
     @Test
     public void test_str_value() {
         for (int id : values) {
-            String str = JSON.toJSONString(id);
-            int id2 = JSON.parseObject(str, int.class);
+            String str = JsonMapper.toJsonString(id);
+            int id2 = JsonMapper.parseJsonObject(str, int.class);
             assertEquals(id, id2);
         }
     }
@@ -177,9 +177,9 @@ public class IntTest {
         for (int id : values) {
             Int1 vo = new Int1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Int1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Int1.class);
+            Int1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Int1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -187,8 +187,8 @@ public class IntTest {
     @Test
     public void test_ascii_value() {
         for (int id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            int id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, int.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            int id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, int.class);
             assertEquals(id, id2);
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/IntValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/IntValueArrayTest.java
index d223fb934..80302ae4b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/IntValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/IntValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -13,7 +13,7 @@ import static junit.framework.TestCase.assertNull;
 public class IntValueArrayTest {
     @Test
     public void test_parse_null() {
-        int[] values = JSON.parseObject("null", int[].class);
+        int[] values = JsonMapper.parseJsonObject("null", int[].class);
         assertNull(values);
     }
 
@@ -25,7 +25,7 @@ public class IntValueArrayTest {
 
     @Test
     public void test_parse() {
-        int[] bytes = JSON.parseObject("[101,102]", int[].class);
+        int[] bytes = JsonMapper.parseJsonObject("[101,102]", int[].class);
         assertEquals(2, bytes.length);
         assertEquals(101, bytes[0]);
         assertEquals(102, bytes[1]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/IntegerTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/IntegerTest.java
index f73f796c7..2a124ee16 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/IntegerTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/IntegerTest.java
@@ -221,9 +221,9 @@ public class IntegerTest {
         for (Integer id : values) {
             Integer1 vo = new Integer1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Integer1 v1 = JSON.parseObject(utf8Bytes, Integer1.class);
+            Integer1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Integer1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -231,16 +231,16 @@ public class IntegerTest {
     @Test
     public void test_utf8_value() {
         for (Integer id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Integer id2 = JSON.parseObject(utf8Bytes, Integer.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Integer id2 = JsonMapper.parseJsonObject(utf8Bytes, Integer.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_utf8_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Integer[] id2 = JSON.parseObject(utf8Bytes, Integer[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Integer[] id2 = JsonMapper.parseJsonObject(utf8Bytes, Integer[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -252,9 +252,9 @@ public class IntegerTest {
         for (Integer id : values) {
             Integer1 vo = new Integer1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Integer1 v1 = JSON.parseObject(str, Integer1.class);
+            Integer1 v1 = JsonMapper.parseJsonObject(str, Integer1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -262,8 +262,8 @@ public class IntegerTest {
     @Test
     public void test_str_value() {
         for (Integer id : values) {
-            String str = JSON.toJSONString(id);
-            Integer id2 = JSON.parseObject(str, Integer.class);
+            String str = JsonMapper.toJsonString(id);
+            Integer id2 = JsonMapper.parseJsonObject(str, Integer.class);
             assertEquals(id, id2);
         }
     }
@@ -278,8 +278,8 @@ public class IntegerTest {
             }
             primitiveValues[i] = values[i];
         }
-        String str = JSON.toJSONString(primitiveValues);
-        int[] id2 = JSON.parseObject(str, int[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        int[] id2 = JsonMapper.parseJsonObject(str, int[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -288,8 +288,8 @@ public class IntegerTest {
 
     @Test
     public void test_str_array() {
-        String str = JSON.toJSONString(values);
-        Integer[] id2 = JSON.parseObject(str, Integer[].class);
+        String str = JsonMapper.toJsonString(values);
+        Integer[] id2 = JsonMapper.parseJsonObject(str, Integer[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -301,9 +301,9 @@ public class IntegerTest {
         for (Integer id : values) {
             Integer1 vo = new Integer1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Integer1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Integer1.class);
+            Integer1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Integer1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -311,16 +311,16 @@ public class IntegerTest {
     @Test
     public void test_ascii_value() {
         for (Integer id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Integer id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Integer.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Integer id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Integer.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_ascii_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Integer[] id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Integer[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Integer[] id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Integer[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -330,35 +330,35 @@ public class IntegerTest {
     @Test
     public void test_str_decimal() {
         String str = "{\"v0000\":1001.0}";
-        Integer1 v1 = JSON.parseObject(str, Integer1.class);
+        Integer1 v1 = JsonMapper.parseJsonObject(str, Integer1.class);
         assertEquals(Integer.valueOf(1001), v1.getV0000());
     }
 
     @Test
     public void test_str_true() {
         String str = "{\"v0000\":true}";
-        Integer1 v1 = JSON.parseObject(str, Integer1.class);
+        Integer1 v1 = JsonMapper.parseJsonObject(str, Integer1.class);
         assertEquals(Integer.valueOf(1), v1.getV0000());
     }
 
     @Test
     public void test_str_false() {
         String str = "{\"v0000\":false}";
-        Integer1 v1 = JSON.parseObject(str, Integer1.class);
+        Integer1 v1 = JsonMapper.parseJsonObject(str, Integer1.class);
         assertEquals(Integer.valueOf(0), v1.getV0000());
     }
 
     @Test
     public void test_str_null() {
         String str = "{\"v0000\":null}";
-        Integer1 v1 = JSON.parseObject(str, Integer1.class);
+        Integer1 v1 = JsonMapper.parseJsonObject(str, Integer1.class);
         assertNull(v1.getV0000());
     }
 
     @Test
     public void test_str_str() {
         String str = "{\"v0000\":\"1001\"}";
-        Integer1 v1 = JSON.parseObject(str, Integer1.class);
+        Integer1 v1 = JsonMapper.parseJsonObject(str, Integer1.class);
         assertEquals(Integer.valueOf(1001), v1.getV0000());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/JSONBSizeTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/JSONBSizeTest.java
index 6b142e42b..7153a2d84 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/JSONBSizeTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/JSONBSizeTest.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.util.IOUtils;
-import com.alibaba.fastjson2.util.JSONBDump;
 import org.junit.jupiter.api.Test;
 
 import java.math.BigDecimal;
@@ -599,7 +598,7 @@ public class JSONBSizeTest {
             assertEquals(val, JSONB.parse(bytes));
             assertEquals(val, JSONB.parseObject(bytes, String.class));
             assertEquals(val, JSONB.parseObject(bytes, CharSequence.class));
-            assertEquals(JSON.toJSONString(val), JSONB.toJSONString(bytes));
+            assertEquals(JsonMapper.toJsonString(val), JSONB.toJSONString(bytes));
         }
     }
 
@@ -613,7 +612,7 @@ public class JSONBSizeTest {
             assertEquals(val, JSONB.parse(bytes));
             assertEquals(val, JSONB.parseObject(bytes, String.class));
             assertEquals(val, JSONB.parseObject(bytes, CharSequence.class));
-            assertEquals(JSON.toJSONString(val), JSONB.toJSONString(bytes));
+            assertEquals(JsonMapper.toJsonString(val), JSONB.toJSONString(bytes));
         }
     }
 
@@ -627,7 +626,7 @@ public class JSONBSizeTest {
             assertEquals(val, JSONB.parse(bytes));
             assertEquals(val, JSONB.parseObject(bytes, String.class));
             assertEquals(val, JSONB.parseObject(bytes, CharSequence.class));
-            assertEquals(JSON.toJSONString(val), JSONB.toJSONString(bytes));
+            assertEquals(JsonMapper.toJsonString(val), JSONB.toJSONString(bytes));
         }
     }
 
@@ -641,7 +640,7 @@ public class JSONBSizeTest {
             assertEquals(val, JSONB.parse(bytes));
             assertEquals(val, JSONB.parseObject(bytes, String.class));
             assertEquals(val, JSONB.parseObject(bytes, CharSequence.class));
-            assertEquals(JSON.toJSONString(val), JSONB.toJSONString(bytes));
+            assertEquals(JsonMapper.toJsonString(val), JSONB.toJSONString(bytes));
         }
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/LargeNumberTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/LargeNumberTest.java
index b1f984c88..58597e101 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/LargeNumberTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/LargeNumberTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -12,7 +12,7 @@ public class LargeNumberTest {
     @Test
     public void test_0() {
         String str = "{\"val\":0.784018486000000000000000000000000000000}";
-        JSONObject object = JSON.parseObject(str);
+        JSONObject object = JsonMapper.parseJsonObject(str);
         assertEquals(new BigDecimal("0.103453752158123073073250785136463577088"), object.get("val"));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/ListFieldTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/ListFieldTest.java
index c2babb96c..38246f43d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/ListFieldTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/ListFieldTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.reader.*;
 import com.alibaba.fastjson2_vo.ListField1;
@@ -89,7 +89,7 @@ public class ListFieldTest {
         vo.v0000 = new ArrayList<>();
         vo.v0001 = new ArrayList<>();
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"v0000\":[],\"v0001\":[]}", str);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/ListStrTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/ListStrTest.java
index 81b89f98e..11628f840 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/ListStrTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/ListStrTest.java
@@ -104,7 +104,7 @@ public class ListStrTest {
     public void test_0() {
         String str = "[1,2,3]";
         Type type = new TypeReference<List<String>>() {}.getType();
-        List<String> array = JSON.parseObject(str, type);
+        List<String> array = JsonMapper.parseJsonObject(str, type);
         assertEquals("1", array.get(0));
 
         JSONWriter jsonWriter = JSONWriter.of();
@@ -114,7 +114,7 @@ public class ListStrTest {
         objectWriter.write(jsonWriter, array);
         assertEquals("[\"1\",\"2\",\"3\"]", jsonWriter.toString());
     }
-    
+
     @Test
     public void test_list() {
         ObjectReaderCreator[] creators = TestUtils.readerCreators();
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/LocalDateTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/LocalDateTest.java
index 6ddbc9836..27615824d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/LocalDateTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/LocalDateTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2_vo.LocalDate1;
 import org.junit.jupiter.api.Test;
@@ -35,9 +35,9 @@ public class LocalDateTest {
     public void test_utf8() {
         LocalDate1 vo = new LocalDate1();
         vo.setDate(LocalDate.now());
-        byte[] utf8 = JSON.toJSONBytes(vo);
+        byte[] utf8 = JsonMapper.toJsonBytes(vo);
 
-        LocalDate1 v1 = JSON.parseObject(utf8, LocalDate1.class);
+        LocalDate1 v1 = JsonMapper.parseJsonObject(utf8, LocalDate1.class);
         assertEquals(vo.getDate(), v1.getDate());
     }
 
@@ -45,16 +45,16 @@ public class LocalDateTest {
     public void test_str() {
         LocalDate1 vo = new LocalDate1();
         vo.setDate(LocalDate.now());
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
 
-        LocalDate1 v1 = JSON.parseObject(str, LocalDate1.class);
+        LocalDate1 v1 = JsonMapper.parseJsonObject(str, LocalDate1.class);
         assertEquals(vo.getDate(), v1.getDate());
     }
 
     @Test
     public void test_str_1() {
         String str = "{\"date\":\"2021年2月3日\"}";
-        LocalDate1 vo = JSON.parseObject(str, LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str, LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(2, vo.getDate().getMonthValue());
         assertEquals(3, vo.getDate().getDayOfMonth());
@@ -63,7 +63,7 @@ public class LocalDateTest {
     @Test
     public void test_str_2() {
         String str = "{\"date\":\"2021年12月1日\"}";
-        LocalDate1 vo = JSON.parseObject(str, LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str, LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -72,7 +72,7 @@ public class LocalDateTest {
     @Test
     public void test_str_3() {
         String str = "{\"date\":\"2021年12月11日\"}";
-        LocalDate1 vo = JSON.parseObject(str, LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str, LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -81,7 +81,7 @@ public class LocalDateTest {
     @Test
     public void test_str_4() {
         String str = "{\"date\":\"2021-12-11\"}";
-        LocalDate1 vo = JSON.parseObject(str, LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str, LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -90,7 +90,7 @@ public class LocalDateTest {
     @Test
     public void test_str_4_utf8() {
         String str = "{\"date\":\"2021-12-11\"}";
-        LocalDate1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -99,7 +99,7 @@ public class LocalDateTest {
     @Test
     public void test_str_5() {
         String str = "{\"date\":\"20211211\"}";
-        LocalDate1 vo = JSON.parseObject(str, LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str, LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -108,7 +108,7 @@ public class LocalDateTest {
     @Test
     public void test_str_5_utf8() {
         String str = "{\"date\":\"20211211\"}";
-        LocalDate1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -118,7 +118,7 @@ public class LocalDateTest {
     @Test
     public void test_str_6() {
         String str = "\r\t\b\f {\"date\":\"2021-2-1\"}";
-        LocalDate1 vo = JSON.parseObject(str, LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str, LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(2, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -128,7 +128,7 @@ public class LocalDateTest {
     public void test_str_6_utf16() {
         String str = "\r\t\b\f {\"date\":\"2021-2-1\"}";
         byte[] strBytes = str.getBytes(StandardCharsets.UTF_16);
-        LocalDate1 vo = JSON.parseObject(strBytes, 0, strBytes.length, StandardCharsets.UTF_16, LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(strBytes, 0, strBytes.length, StandardCharsets.UTF_16, LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(2, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -138,7 +138,7 @@ public class LocalDateTest {
     public void test_str_6_utf16_2() {
         String str = "\r\t\b\f {\"date\":\"2021-2-1\"}";
         byte[] strBytes = str.getBytes(StandardCharsets.UTF_16);
-        LocalDate1 vo = JSON.parseObject(strBytes, 2, strBytes.length - 2, StandardCharsets.UTF_16, LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(strBytes, 2, strBytes.length - 2, StandardCharsets.UTF_16, LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(2, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -147,7 +147,7 @@ public class LocalDateTest {
     @Test
     public void test_str_6_utf8() {
         String str = "\r\t\b\f {\"date\":\"2021-2-1\"}";
-        LocalDate1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDate1.class);
+        LocalDate1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDate1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(2, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/LocalDateTimeTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/LocalDateTimeTest.java
index 18fcd54b5..fdf2bcb50 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/LocalDateTimeTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/LocalDateTimeTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2_vo.LocalDateTime1;
 import org.junit.jupiter.api.Test;
@@ -62,7 +62,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_jsonb_str_1() {
         for (LocalDateTime dateTime : dateTimes) {
-            String str = (String) JSON.parse(JSON.toJSONString(dateTime));
+            String str = (String) JsonMapper.parseJson(JsonMapper.toJsonString(dateTime));
             byte[] jsonbBytes = JSONB.toBytes(str);
 
             LocalDateTime ldt = JSONB.parseObject(jsonbBytes, LocalDateTime.class);
@@ -75,9 +75,9 @@ public class LocalDateTimeTest {
         for (LocalDateTime dateTime : dateTimes) {
             LocalDateTime1 vo = new LocalDateTime1();
             vo.setDate(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            LocalDateTime1 v1 = JSON.parseObject(utf8Bytes, LocalDateTime1.class);
+            LocalDateTime1 v1 = JsonMapper.parseJsonObject(utf8Bytes, LocalDateTime1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -87,9 +87,9 @@ public class LocalDateTimeTest {
         for (LocalDateTime dateTime : dateTimes) {
             LocalDateTime1 vo = new LocalDateTime1();
             vo.setDate(dateTime);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            LocalDateTime1 v1 = JSON.parseObject(str, LocalDateTime1.class);
+            LocalDateTime1 v1 = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -99,9 +99,9 @@ public class LocalDateTimeTest {
         for (LocalDateTime dateTime : dateTimes) {
             LocalDateTime1 vo = new LocalDateTime1();
             vo.setDate(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            LocalDateTime1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, LocalDateTime1.class);
+            LocalDateTime1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, LocalDateTime1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -109,7 +109,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_1() {
         String str = "{\"date\":\"2021年2月3日\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(2, vo.getDate().getMonthValue());
         assertEquals(3, vo.getDate().getDayOfMonth());
@@ -118,7 +118,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_2() {
         String str = "{\"date\":\"2021年12月1日\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -127,7 +127,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_3() {
         String str = "{\"date\":\"2021年12月11日\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -136,7 +136,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_3_h() {
         String str = "{\"date\":\"2021년12월11일\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -145,7 +145,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_1() {
         String str = "{\"date\":\"2021年12月1日\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -154,7 +154,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_1_h() {
         String str = "{\"date\":\"2021년12월1일\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -163,7 +163,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_2() {
         String str = "{\"date\":\"2021年1月21日\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(1, vo.getDate().getMonthValue());
         assertEquals(21, vo.getDate().getDayOfMonth());
@@ -172,7 +172,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_2_h() {
         String str = "{\"date\":\"2021년1월21일\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(1, vo.getDate().getMonthValue());
         assertEquals(21, vo.getDate().getDayOfMonth());
@@ -181,7 +181,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_3() {
         String str = "{\"date\":\"2021-12-11\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -190,7 +190,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_3_utf8() {
         String str = "{\"date\":\"2021-12-11\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -199,7 +199,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_4() {
         String str = "{\"date\":\"2021/12/11\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -208,7 +208,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_4_utf8() {
         String str = "{\"date\":\"2021/12/11\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -217,7 +217,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_5() {
         String str = "{\"date\":\"11.12.2021\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -226,7 +226,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_5_utf8() {
         String str = "{\"date\":\"11.12.2021\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -235,7 +235,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_6() {
         String str = "{\"date\":\"11-12-2021\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -244,7 +244,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_10_6_utf8() {
         String str = "{\"date\":\"11-12-2021\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -253,7 +253,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_5() {
         String str = "{\"date\":\"20211211\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -262,7 +262,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_5_utf8() {
         String str = "{\"date\":\"20211211\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -272,7 +272,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_6() {
         String str = "{\"date\":\"2021-2-1\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(2, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -281,7 +281,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_6_utf8() {
         String str = "{\"date\":\"2021-2-1\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(2, vo.getDate().getMonthValue());
         assertEquals(1, vo.getDate().getDayOfMonth());
@@ -290,7 +290,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_16_0() {
         String str = "{\"date\":\"2021-12-13 12:13\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(13, vo.getDate().getDayOfMonth());
@@ -303,7 +303,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_16_0_utf8() {
         String str = "{\"date\":\"2021-12-13 12:13\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(13, vo.getDate().getDayOfMonth());
@@ -316,7 +316,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_17_0() {
         String str = "{\"date\":\"2021-1-2 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(1, vo.getDate().getMonthValue());
         assertEquals(2, vo.getDate().getDayOfMonth());
@@ -329,7 +329,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_17_0_utf8() {
         String str = "{\"date\":\"2021-1-2 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(1, vo.getDate().getMonthValue());
         assertEquals(2, vo.getDate().getDayOfMonth());
@@ -342,7 +342,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_17_1() {
         String str = "{\"date\":\"2021-12-13T12:13Z\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(13, vo.getDate().getDayOfMonth());
@@ -355,7 +355,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_17_1_utf8() {
         String str = "{\"date\":\"2021-12-13T12:13Z\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(13, vo.getDate().getDayOfMonth());
@@ -368,7 +368,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_18_0() {
         String str = "{\"date\":\"2021-1-11 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(1, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -381,7 +381,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_18_0_utf8() {
         String str = "{\"date\":\"2021-1-11 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(1, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -394,7 +394,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_18_1() {
         String str = "{\"date\":\"2021-12-3 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(3, vo.getDate().getDayOfMonth());
@@ -407,7 +407,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_18_1_utf8() {
         String str = "{\"date\":\"2021-12-3 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(3, vo.getDate().getDayOfMonth());
@@ -420,7 +420,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_19() {
         String str = "{\"date\":\"2021-12-11 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -429,7 +429,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_19_utf8() {
         String str = "{\"date\":\"2021-12-11 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -438,7 +438,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_19_1() {
         String str = "{\"date\":\"2021/12/11 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str, LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str, LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
@@ -447,7 +447,7 @@ public class LocalDateTimeTest {
     @Test
     public void test_str_19_1_utf8() {
         String str = "{\"date\":\"2021/12/11 12:13:14\"}";
-        LocalDateTime1 vo = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
+        LocalDateTime1 vo = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), LocalDateTime1.class);
         assertEquals(2021, vo.getDate().getYear());
         assertEquals(12, vo.getDate().getMonthValue());
         assertEquals(11, vo.getDate().getDayOfMonth());
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/LocalTimeTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/LocalTimeTest.java
index 0dd70f18b..69cf4d4e2 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/LocalTimeTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/LocalTimeTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2_vo.LocalTime1;
 import org.junit.jupiter.api.Test;
@@ -51,9 +51,9 @@ public class LocalTimeTest {
         for (LocalTime time : times) {
             LocalTime1 vo = new LocalTime1();
             vo.setDate(time);
-            byte[] jsonbBytes = JSON.toJSONBytes(vo);
+            byte[] jsonbBytes = JsonMapper.toJsonBytes(vo);
 
-            LocalTime1 v1 = JSON.parseObject(jsonbBytes, LocalTime1.class);
+            LocalTime1 v1 = JsonMapper.parseJsonObject(jsonbBytes, LocalTime1.class);
             assertEquals(vo.getDate(), v1.getDate());
         }
     }
@@ -63,9 +63,9 @@ public class LocalTimeTest {
         for (LocalTime time : times) {
             LocalTime1 vo = new LocalTime1();
             vo.setDate(time);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            LocalTime1 v1 = JSON.parseObject(str, LocalTime1.class);
+            LocalTime1 v1 = JsonMapper.parseJsonObject(str, LocalTime1.class);
             if (v1 == null) {
                 fail();
             }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/LocaleTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/LocaleTest.java
index 845d7fe4f..a16be8741 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/LocaleTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/LocaleTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -14,10 +14,10 @@ public class LocaleTest {
         VO vo = new VO();
         vo.locale = Locale.CHINA;
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"locale\":\"zh_CN\"}", str);
 
-        VO v2 = JSON.parseObject(str, VO.class);
+        VO v2 = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(vo.locale, v2.locale);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/LongTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/LongTest.java
index 1e0dced5e..8f6f045f7 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/LongTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/LongTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2.JSONWriter;
@@ -244,9 +244,9 @@ public class LongTest {
         for (Long id : values) {
             Long1 vo = new Long1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Long1 v1 = JSON.parseObject(utf8Bytes, Long1.class);
+            Long1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Long1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -254,16 +254,16 @@ public class LongTest {
     @Test
     public void test_utf8_value() {
         for (Long id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Long id2 = JSON.parseObject(utf8Bytes, Long.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Long id2 = JsonMapper.parseJsonObject(utf8Bytes, Long.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_utf8_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Long[] id2 = JSON.parseObject(utf8Bytes, Long[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Long[] id2 = JsonMapper.parseJsonObject(utf8Bytes, Long[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -275,9 +275,9 @@ public class LongTest {
         for (Long id : values) {
             Long1 vo = new Long1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Long1 v1 = JSON.parseObject(str, Long1.class);
+            Long1 v1 = JsonMapper.parseJsonObject(str, Long1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -285,43 +285,43 @@ public class LongTest {
     @Test
     public void test_str_decimal() {
         String str = "{\"v0000\":1001.0}";
-        Long1 v1 = JSON.parseObject(str, Long1.class);
+        Long1 v1 = JsonMapper.parseJsonObject(str, Long1.class);
         assertEquals(Long.valueOf(1001), v1.getV0000());
     }
 
     @Test
     public void test_str_true() {
         String str = "{\"v0000\":true}";
-        Long1 v1 = JSON.parseObject(str, Long1.class);
+        Long1 v1 = JsonMapper.parseJsonObject(str, Long1.class);
         assertEquals(Long.valueOf(1), v1.getV0000());
     }
 
     @Test
     public void test_str_false() {
         String str = "{\"v0000\":false}";
-        Long1 v1 = JSON.parseObject(str, Long1.class);
+        Long1 v1 = JsonMapper.parseJsonObject(str, Long1.class);
         assertEquals(Long.valueOf(0), v1.getV0000());
     }
 
     @Test
     public void test_str_null() {
         String str = "{\"v0000\":null}";
-        Long1 v1 = JSON.parseObject(str, Long1.class);
+        Long1 v1 = JsonMapper.parseJsonObject(str, Long1.class);
         assertNull(v1.getV0000());
     }
 
     @Test
     public void test_str_str() {
         String str = "{\"v0000\":\"1001\"}";
-        Long1 v1 = JSON.parseObject(str, Long1.class);
+        Long1 v1 = JsonMapper.parseJsonObject(str, Long1.class);
         assertEquals(Long.valueOf(1001), v1.getV0000());
     }
 
     @Test
     public void test_str_value() {
         for (Long id : values) {
-            String str = JSON.toJSONString(id);
-            Long id2 = JSON.parseObject(str, Long.class);
+            String str = JsonMapper.toJsonString(id);
+            Long id2 = JsonMapper.parseJsonObject(str, Long.class);
             assertEquals(id, id2);
         }
     }
@@ -336,8 +336,8 @@ public class LongTest {
             }
             primitiveValues[i] = values[i];
         }
-        String str = JSON.toJSONString(primitiveValues);
-        long[] id2 = JSON.parseObject(str, long[].class);
+        String str = JsonMapper.toJsonString(primitiveValues);
+        long[] id2 = JsonMapper.parseJsonObject(str, long[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(primitiveValues[i], id2[i]);
@@ -346,8 +346,8 @@ public class LongTest {
 
     @Test
     public void test_str_array() {
-        String str = JSON.toJSONString(values);
-        Long[] id2 = JSON.parseObject(str, Long[].class);
+        String str = JsonMapper.toJsonString(values);
+        Long[] id2 = JsonMapper.parseJsonObject(str, Long[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
@@ -359,9 +359,9 @@ public class LongTest {
         for (Long id : values) {
             Long1 vo = new Long1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Long1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Long1.class);
+            Long1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Long1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -369,16 +369,16 @@ public class LongTest {
     @Test
     public void test_ascii_value() {
         for (Long id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Long id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Long.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Long id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Long.class);
             assertEquals(id, id2);
         }
     }
 
     @Test
     public void test_ascii_array() {
-        byte[] utf8Bytes = JSON.toJSONBytes(values);
-        Long[] id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Long[].class);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(values);
+        Long[] id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Long[].class);
         assertEquals(values.length, id2.length);
         for (int i = 0; i < id2.length; ++i) {
             assertEquals(values[i], id2[i]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/LongValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/LongValueArrayTest.java
index 3d9888f35..8b8d753bd 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/LongValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/LongValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -12,7 +12,7 @@ import static junit.framework.TestCase.assertNull;
 public class LongValueArrayTest {
     @Test
     public void test_parse_null() {
-        long[] values = JSON.parseObject("null", long[].class);
+        long[] values = JsonMapper.parseJsonObject("null", long[].class);
         assertNull(values);
     }
 
@@ -24,7 +24,7 @@ public class LongValueArrayTest {
 
     @Test
     public void test_parse() {
-        long[] bytes = JSON.parseObject("[101,102]", long[].class);
+        long[] bytes = JsonMapper.parseJsonObject("[101,102]", long[].class);
         assertEquals(2, bytes.length);
         assertEquals(101, bytes[0]);
         assertEquals(102, bytes[1]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/MapEntryTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/MapEntryTest.java
index 4b5c49e0d..9097e9a2b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/MapEntryTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/MapEntryTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -15,9 +15,9 @@ public class MapEntryTest {
 
     @Test
     public void test_str() {
-        String str = JSON.toJSONString(entry);
+        String str = JsonMapper.toJsonString(entry);
         assertEquals("{\"id\":101}", str);
-        Map.Entry entry = JSON.parseObject(str, Map.Entry.class);
+        Map.Entry entry = JsonMapper.parseJsonObject(str, Map.Entry.class);
         assertEquals("id", entry.getKey());
         assertEquals(101, entry.getValue());
         entry.setValue(102);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/MapTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/MapTest.java
index e6e826263..a815409ae 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/MapTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/MapTest.java
@@ -12,7 +12,7 @@ public class MapTest {
     @Test
     public void test_read() throws Exception {
         String str = "{\"properties\":{\"prop1\":0.0}}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals("0.0", vo.getProperties().get("prop1"));
     }
 
@@ -23,7 +23,7 @@ public class MapTest {
         vo.setProperties(map);
 
         String str = "{\"properties\":{\"prop1\":0.0}}";
-        assertEquals(str, JSON.toJSONString(vo));
+        assertEquals(str, JsonMapper.toJsonString(vo));
     }
 
     @Test
@@ -169,11 +169,11 @@ public class MapTest {
         String key = "中国®";
         Map map = Collections.singletonMap(key, 1);
 
-        String str = JSON.toJSONString(map);
-        assertEquals(1, JSON.parseObject(str).get(key));
+        String str = JsonMapper.toJsonString(map);
+        assertEquals(1, JsonMapper.parseJsonObject(str).get(key));
 
-        byte[] utf8Bytes = JSON.toJSONBytes(map);
-        assertEquals(1, JSON.parseObject(utf8Bytes).get(key));
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(map);
+        assertEquals(1, JsonMapper.parseJsonObject(utf8Bytes).get(key));
     }
 
     @Test
@@ -181,12 +181,12 @@ public class MapTest {
         String key = "\\\r\n中国®";
         Map map = Collections.singletonMap(key, 1);
 
-        String str = JSON.toJSONString(map);
-        assertEquals(1, JSON.parseObject(str).get(key));
+        String str = JsonMapper.toJsonString(map);
+        assertEquals(1, JsonMapper.parseJsonObject(str).get(key));
 
-        byte[] utf8Bytes = JSON.toJSONBytes(map);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(map);
         assertEquals(1
-                , JSON.parseObject(utf8Bytes)
+                , JsonMapper.parseJsonObject(utf8Bytes)
                         .get(key));
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/NumberArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/NumberArrayTest.java
index 11d524f6d..3f67ea82e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/NumberArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/NumberArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2.JSONObject;
@@ -19,7 +19,7 @@ import static junit.framework.TestCase.assertNull;
 public class NumberArrayTest {
     @Test
     public void test_parse_null() {
-        Number[] values = JSON.parseObject("null", Number[].class);
+        Number[] values = JsonMapper.parseJsonObject("null", Number[].class);
         assertNull(values);
     }
 
@@ -31,7 +31,7 @@ public class NumberArrayTest {
 
     @Test
     public void test_parse() {
-        Number[] bytes = JSON.parseObject("[101,102]", Number[].class);
+        Number[] bytes = JsonMapper.parseJsonObject("[101,102]", Number[].class);
         assertEquals(2, bytes.length);
         assertEquals(101, bytes[0]);
         assertEquals(102, bytes[1]);
@@ -72,27 +72,27 @@ public class NumberArrayTest {
 
             byte[] jsonbBytes = JSONB.toBytes(vo);
             Number1 vo2 = JSONB.parseObject(jsonbBytes, Number1.class);
-            assertEquals(JSON.toJSONString(vo.getValue())
-                    , JSON.toJSONString(vo2.getValue()));
+            assertEquals(JsonMapper.toJsonString(vo.getValue())
+                    , JsonMapper.toJsonString(vo2.getValue()));
 
             JSONBDump.dump(jsonbBytes);
 
             JSONObject jsonObject = JSONB.parseObject(jsonbBytes, JSONObject.class);
-            assertEquals(JSON.toJSONString(vo.getValue())
-                    , JSON.toJSONString(jsonObject.get("value")));
+            assertEquals(JsonMapper.toJsonString(vo.getValue())
+                    , JsonMapper.toJsonString(jsonObject.get("value")));
         }
 
         {
             byte[] jsonbBytes = JSONB.toBytes(Collections.singletonMap("value", "123"));
             Number1 vo2 = JSONB.parseObject(jsonbBytes, Number1.class);
             assertEquals("123"
-                    , JSON.toJSONString(vo2.getValue()));
+                    , JsonMapper.toJsonString(vo2.getValue()));
         }
         {
             byte[] jsonbBytes = JSONB.toBytes(Collections.singletonMap("value", "12345678901234567890123456789012345678901234567890123456789012345678901234567890"));
             Number1 vo2 = JSONB.parseObject(jsonbBytes, Number1.class);
             assertEquals("12345678901234567890123456789012345678901234567890123456789012345678901234567890"
-                    , JSON.toJSONString(vo2.getValue()));
+                    , JsonMapper.toJsonString(vo2.getValue()));
         }
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalDoubleTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalDoubleTest.java
index 32a8aef6a..0614e9d83 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalDoubleTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalDoubleTest.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.util.JSONBDump;
 import org.junit.jupiter.api.Test;
 
 import java.util.Collections;
@@ -16,9 +15,9 @@ public class OptinalDoubleTest {
     @Test
     public void test_0() {
         String str = "{\"value\":123.0}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(123.0D, vo.value.getAsDouble());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals(str, str2);
     }
 
@@ -35,9 +34,9 @@ public class OptinalDoubleTest {
     @Test
     public void test_empty() {
         String str = "{\"value\":null}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(false, vo.value.isPresent());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals(str, str2);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalIntTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalIntTest.java
index 5d8eae018..ca713bf37 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalIntTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalIntTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -15,9 +15,9 @@ public class OptinalIntTest {
     @Test
     public void test_0() {
         String str = "{\"value\":123}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(123, vo.value.getAsInt());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals(str, str2);
     }
 
@@ -31,9 +31,9 @@ public class OptinalIntTest {
     @Test
     public void test_empty() {
         String str = "{\"value\":null}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(false, vo.value.isPresent());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals(str, str2);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalLongTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalLongTest.java
index 8e4f2940c..536db18e9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalLongTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalLongTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -15,9 +15,9 @@ public class OptinalLongTest {
     @Test
     public void test_0() {
         String str = "{\"value\":123}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(123, vo.value.getAsLong());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals(str, str2);
     }
 
@@ -31,9 +31,9 @@ public class OptinalLongTest {
     @Test
     public void test_empty() {
         String str = "{\"value\":null}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(false, vo.value.isPresent());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals(str, str2);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalTest.java
index 9e864f17d..2aeeaf0aa 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/OptinalTest.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.util.JSONBDump;
 import org.junit.jupiter.api.Test;
 
 import java.util.Collections;
@@ -16,9 +15,9 @@ public class OptinalTest {
     @Test
     public void test_0() {
         String str = "{\"value\":123}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals("123", vo.value.get());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals("{\"value\":\"123\"}", str2);
     }
 
@@ -27,16 +26,16 @@ public class OptinalTest {
         byte[] bytes = JSONB.toBytes(Collections.singletonMap("value", 123));
         VO vo = JSONB.parseObject(bytes, VO.class);
         assertEquals("123", vo.value.get());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals("{\"value\":\"123\"}", str2);
     }
 
     @Test
     public void test_empty() {
         String str = "{\"value\":null}";
-        VO vo = JSON.parseObject(str, VO.class);
+        VO vo = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(false, vo.value.isPresent());
-        String str2 = JSON.toJSONString(vo);
+        String str2 = JsonMapper.toJsonString(vo);
         assertEquals(str, str2);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/ShortTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/ShortTest.java
index 9d44b377e..35dfc30aa 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/ShortTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/ShortTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONBTest;
 import com.alibaba.fastjson2.JSONWriter;
@@ -179,9 +179,9 @@ public class ShortTest {
         for (Short id : values) {
             Short1 vo = new Short1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Short1 v1 = JSON.parseObject(utf8Bytes, Short1.class);
+            Short1 v1 = JsonMapper.parseJsonObject(utf8Bytes, Short1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -189,8 +189,8 @@ public class ShortTest {
     @Test
     public void test_utf8_value() {
         for (Short id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Short id2 = JSON.parseObject(utf8Bytes, Short.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Short id2 = JsonMapper.parseJsonObject(utf8Bytes, Short.class);
             assertEquals(id, id2);
         }
     }
@@ -200,9 +200,9 @@ public class ShortTest {
         for (Short id : values) {
             Short1 vo = new Short1();
             vo.setV0000(id);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            Short1 v1 = JSON.parseObject(str, Short1.class);
+            Short1 v1 = JsonMapper.parseJsonObject(str, Short1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -210,8 +210,8 @@ public class ShortTest {
     @Test
     public void test_str_value() {
         for (Short id : values) {
-            String str = JSON.toJSONString(id);
-            Short id2 = JSON.parseObject(str, Short.class);
+            String str = JsonMapper.toJsonString(id);
+            Short id2 = JsonMapper.parseJsonObject(str, Short.class);
             assertEquals(id, id2);
         }
     }
@@ -221,9 +221,9 @@ public class ShortTest {
         for (Short id : values) {
             Short1 vo = new Short1();
             vo.setV0000(id);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            Short1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Short1.class);
+            Short1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Short1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -231,8 +231,8 @@ public class ShortTest {
     @Test
     public void test_ascii_value() {
         for (Short id : values) {
-            byte[] utf8Bytes = JSON.toJSONBytes(id);
-            Short id2 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Short.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(id);
+            Short id2 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, Short.class);
             assertEquals(id, id2);
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/ShortValueArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/ShortValueArrayTest.java
index 305fb78bf..0f8c633f8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/ShortValueArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/ShortValueArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -13,7 +13,7 @@ import static junit.framework.TestCase.assertNull;
 public class ShortValueArrayTest {
     @Test
     public void test_parse_null() {
-        short[] values = JSON.parseObject("null", short[].class);
+        short[] values = JsonMapper.parseJsonObject("null", short[].class);
         assertNull(values);
     }
 
@@ -25,7 +25,7 @@ public class ShortValueArrayTest {
 
     @Test
     public void test_parse() {
-        short[] bytes = JSON.parseObject("[101,102]", short[].class);
+        short[] bytes = JsonMapper.parseJsonObject("[101,102]", short[].class);
         assertEquals(2, bytes.length);
         assertEquals(101, bytes[0]);
         assertEquals(102, bytes[1]);
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/StringArrayTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/StringArrayTest.java
index 68fd43cc7..10cfa0107 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/StringArrayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/StringArrayTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -10,20 +10,20 @@ public class StringArrayTest {
     @Test
     public void test_writeNull() {
         assertEquals("{\"values\":null}"
-                , JSON.toJSONString(new VO(), JSONWriter.Feature.WriteNulls));
+                , JsonMapper.toJsonString(new VO(), JSONWriter.Feature.WriteNulls));
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO(), JSONWriter.Feature.WriteNulls)));
     }
 
     @Test
     public void test_writeNull2() {
         assertEquals("{}"
-                , JSON.toJSONString(new VO2()));
+                , JsonMapper.toJsonString(new VO2()));
 
         assertEquals("{\"values\":null}",
                 new String(
-                        JSON.toJSONBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
+                        JsonMapper.toJsonBytes(new VO2(), JSONWriter.Feature.WriteNulls)));
     }
 
     public static class VO {
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/StringTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/StringTest.java
index 8bed2b48c..e08cdae61 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/StringTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/StringTest.java
@@ -1,11 +1,9 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
-import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.util.IOUtils;
-import com.alibaba.fastjson2.util.JDKUtils;
 import com.alibaba.fastjson2.writer.*;
 import com.alibaba.fastjson2_vo.String1;
 import org.junit.jupiter.api.Test;
@@ -45,14 +43,14 @@ public class StringTest {
         vo.setId(val);
 
         {
-            String str = JSON.toJSONString(vo);
-            String1 o2 = JSON.parseObject(str, String1.class);
+            String str = JsonMapper.toJsonString(vo);
+            String1 o2 = JsonMapper.parseJsonObject(str, String1.class);
             assertEquals(vo.getId(), o2.getId());
         }
 
         {
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
-            String1 o3 = JSON.parseObject(utf8Bytes, String1.class);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
+            String1 o3 = JsonMapper.parseJsonObject(utf8Bytes, String1.class);
             assertEquals(vo.getId(), o3.getId());
         }
     }
@@ -65,16 +63,16 @@ public class StringTest {
         vo.setId(val);
 
         {
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
             System.out.println(str);
-            String1 o2 = JSON.parseObject(str, String1.class);
+            String1 o2 = JsonMapper.parseJsonObject(str, String1.class);
             assertEquals(vo.getId(), o2.getId());
         }
 
         {
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
             System.out.println(new String(utf8Bytes));
-            String1 o3 = JSON.parseObject(utf8Bytes, String1.class);
+            String1 o3 = JsonMapper.parseJsonObject(utf8Bytes, String1.class);
             assertEquals(vo.getId(), o3.getId());
         }
     }
@@ -86,12 +84,12 @@ public class StringTest {
         byte[] utf8Bytes = str.getBytes(StandardCharsets.UTF_8);
 
         {
-            String1 o2 = JSON.parseObject(str, String1.class);
+            String1 o2 = JsonMapper.parseJsonObject(str, String1.class);
             assertEquals(Character.toString(ch), o2.getId());
         }
 
         {
-            String1 o3 = JSON.parseObject(utf8Bytes, String1.class);
+            String1 o3 = JsonMapper.parseJsonObject(utf8Bytes, String1.class);
             assertEquals(Character.toString(ch), o3.getId());
         }
     }
@@ -103,12 +101,12 @@ public class StringTest {
         byte[] utf8Bytes = str.getBytes(StandardCharsets.UTF_8);
 
         {
-            String1 o2 = JSON.parseObject(str, String1.class);
+            String1 o2 = JsonMapper.parseJsonObject(str, String1.class);
             assertEquals("\"" + ch, o2.getId());
         }
 
         {
-            String1 o3 = JSON.parseObject(utf8Bytes, String1.class);
+            String1 o3 = JsonMapper.parseJsonObject(utf8Bytes, String1.class);
             assertEquals("\"" + ch, o3.getId());
         }
     }
@@ -120,12 +118,12 @@ public class StringTest {
         byte[] utf8Bytes = str.getBytes(StandardCharsets.UTF_8);
 
         {
-            String1 o2 = JSON.parseObject(str, String1.class);
+            String1 o2 = JsonMapper.parseJsonObject(str, String1.class);
             assertEquals("\"" + ch, o2.getId());
         }
 
         {
-            String1 o3 = JSON.parseObject(utf8Bytes, String1.class);
+            String1 o3 = JsonMapper.parseJsonObject(utf8Bytes, String1.class);
             assertEquals("\"" + ch, o3.getId());
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/TimeZoneTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/TimeZoneTest.java
index b895a77ac..4a4e164d2 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/TimeZoneTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/TimeZoneTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
 
@@ -14,10 +14,10 @@ public class TimeZoneTest {
         VO vo = new VO();
         vo.value = TimeZone.getTimeZone("Asia/Shanghai");
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"value\":\"Asia/Shanghai\"}", str);
 
-        VO v2 = JSON.parseObject(str, VO.class);
+        VO v2 = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(vo.value, v2.value);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest.java
index 0f4954db2..3bfeb820c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest.java
@@ -3,10 +3,6 @@ package com.alibaba.fastjson2.primitves;
 import com.alibaba.fastjson2.*;
 import com.alibaba.fastjson2.util.JSONBDump;
 import com.alibaba.fastjson2.writer.*;
-import com.alibaba.fastjson2.reader.ObjectReader;
-import com.alibaba.fastjson2.reader.ObjectReaderCreator;
-import com.alibaba.fastjson2.reader.ObjectReaderCreatorASM;
-import com.alibaba.fastjson2.reader.ObjectReaderCreatorLambda;
 import com.alibaba.fastjson2_vo.UUID1;
 import com.alibaba.fastjson2_vo.UUIDFIeld2;
 import org.junit.jupiter.api.Test;
@@ -40,9 +36,9 @@ public class UUIDTest {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            UUID1 v1 = JSON.parseObject(utf8Bytes, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(utf8Bytes, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -52,9 +48,9 @@ public class UUIDTest {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            UUID1 v1 = JSON.parseObject(str, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(str, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -64,9 +60,9 @@ public class UUIDTest {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            UUID1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -78,14 +74,14 @@ public class UUIDTest {
             UUIDFIeld2 vo = new UUIDFIeld2();
             vo.v0000 = UUID.fromString("d9ac58be-c854-496b-b550-56f0b773d241");
 
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
             assertEquals("{\"v0000\":\"d9ac58be-c854-496b-b550-56f0b773d241\"}", str);
         }
         {
             UUIDFIeld2 vo = new UUIDFIeld2();
             vo.v0001 = UUID.fromString("d9ac58be-c854-496b-b550-56f0b773d241");
 
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
             assertEquals("{\"v0001\":\"d9ac58be-c854-496b-b550-56f0b773d241\"}", str);
         }
         {
@@ -93,7 +89,7 @@ public class UUIDTest {
             vo.v0000 = UUID.fromString("d9ac58be-c854-496b-b550-56f0b773d241");
             vo.v0001 = UUID.fromString("d9ac58be-c854-496b-b550-56f0b773d241");
 
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
             assertEquals("{\"v0000\":\"d9ac58be-c854-496b-b550-56f0b773d241\",\"v0001\":\"d9ac58be-c854-496b-b550-56f0b773d241\"}", str);
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest2.java b/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest2.java
index 57ee59113..ffe1dd1b3 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2_vo.UUID1;
 import org.junit.jupiter.api.Test;
@@ -33,10 +33,10 @@ public class UUIDTest2 {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(
                     Collections.singletonMap("id", vo.getId().toString()));
 
-            UUID1 v1 = JSON.parseObject(utf8Bytes, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(utf8Bytes, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -46,11 +46,11 @@ public class UUIDTest2 {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            String str = JSON.toJSONString(
+            String str = JsonMapper.toJsonString(
                     Collections.singletonMap("id", vo.getId().toString())
             );
 
-            UUID1 v1 = JSON.parseObject(str, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(str, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -60,11 +60,11 @@ public class UUIDTest2 {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(
                     Collections.singletonMap("id", vo.getId().toString())
             );
 
-            UUID1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest3.java b/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest3.java
index 5f0106507..f44ec48ba 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/UUIDTest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2_vo.UUID1;
 import org.junit.jupiter.api.Test;
@@ -38,10 +38,10 @@ public class UUIDTest3 {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(
                     Collections.singletonMap("id", toString(vo.getId())));
 
-            UUID1 v1 = JSON.parseObject(utf8Bytes, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(utf8Bytes, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -51,11 +51,11 @@ public class UUIDTest3 {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            String str = JSON.toJSONString(
+            String str = JsonMapper.toJsonString(
                     Collections.singletonMap("id", toString(vo.getId()))
             );
 
-            UUID1 v1 = JSON.parseObject(str, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(str, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
@@ -65,11 +65,11 @@ public class UUIDTest3 {
         for (UUID dateTime : values) {
             UUID1 vo = new UUID1();
             vo.setId(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(
                     Collections.singletonMap("id", toString(vo.getId()))
             );
 
-            UUID1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, UUID1.class);
+            UUID1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, UUID1.class);
             assertEquals(vo.getId(), v1.getId());
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/ZoneIdTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/ZoneIdTest.java
index 6ad9c94eb..f0f457f6a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/ZoneIdTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/ZoneIdTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2_vo.ZoneId1;
 import org.junit.jupiter.api.Test;
@@ -15,10 +15,10 @@ public class ZoneIdTest {
         ZoneId1 vo = new ZoneId1();
         vo.setV0000(ZoneId.of("Asia/Shanghai"));
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"v0000\":\"Asia/Shanghai\"}", str);
 
-        ZoneId1 v2 = JSON.parseObject(str, ZoneId1.class);
+        ZoneId1 v2 = JsonMapper.parseJsonObject(str, ZoneId1.class);
         assertEquals(vo.getV0000(), v2.getV0000());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/primitves/ZonedDateTimeTest.java b/core/src/test/java/com/alibaba/fastjson2/primitves/ZonedDateTimeTest.java
index f0b4fa1ba..56555efa1 100644
--- a/core/src/test/java/com/alibaba/fastjson2/primitves/ZonedDateTimeTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/primitves/ZonedDateTimeTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2_vo.ZonedDateTime1;
 import org.junit.jupiter.api.Test;
@@ -92,9 +92,9 @@ public class ZonedDateTimeTest {
         for (ZonedDateTime dateTime : dateTimes) {
             ZonedDateTime1 vo = new ZonedDateTime1();
             vo.setV0000(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            ZonedDateTime1 v1 = JSON.parseObject(utf8Bytes, ZonedDateTime1.class);
+            ZonedDateTime1 v1 = JsonMapper.parseJsonObject(utf8Bytes, ZonedDateTime1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -106,9 +106,9 @@ public class ZonedDateTimeTest {
 
             ZonedDateTime1 vo = new ZonedDateTime1();
             vo.setV0000(dateTime);
-            String str = JSON.toJSONString(vo);
+            String str = JsonMapper.toJsonString(vo);
 
-            ZonedDateTime1 v1 = JSON.parseObject(str, ZonedDateTime1.class);
+            ZonedDateTime1 v1 = JsonMapper.parseJsonObject(str, ZonedDateTime1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
@@ -118,9 +118,9 @@ public class ZonedDateTimeTest {
         for (ZonedDateTime dateTime : dateTimes) {
             ZonedDateTime1 vo = new ZonedDateTime1();
             vo.setV0000(dateTime);
-            byte[] utf8Bytes = JSON.toJSONBytes(vo);
+            byte[] utf8Bytes = JsonMapper.toJsonBytes(vo);
 
-            ZonedDateTime1 v1 = JSON.parseObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, ZonedDateTime1.class);
+            ZonedDateTime1 v1 = JsonMapper.parseJsonObject(utf8Bytes, 0, utf8Bytes.length, StandardCharsets.US_ASCII, ZonedDateTime1.class);
             assertEquals(vo.getV0000(), v1.getV0000());
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/support/ApacheTripleTest.java b/core/src/test/java/com/alibaba/fastjson2/support/ApacheTripleTest.java
index fc1a33e20..669213680 100644
--- a/core/src/test/java/com/alibaba/fastjson2/support/ApacheTripleTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/support/ApacheTripleTest.java
@@ -1,14 +1,11 @@
 package com.alibaba.fastjson2.support;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2.autoType.AutoTypeTest16_pairKey;
 import com.alibaba.fastjson2.util.JSONBDump;
-import org.apache.commons.lang3.tuple.MutablePair;
 import org.apache.commons.lang3.tuple.MutableTriple;
-import org.apache.commons.lang3.tuple.Pair;
 import org.apache.commons.lang3.tuple.Triple;
 import org.junit.jupiter.api.Test;
 
@@ -58,7 +55,7 @@ public class ApacheTripleTest {
     @Test
     public void test_1() throws Exception {
         String str = "{\"left\":101,\"middle\":102,\"right\":103}";
-        Triple triple = JSON.parseObject(str, Triple.class);
+        Triple triple = JsonMapper.parseJsonObject(str, Triple.class);
         assertEquals(101, triple.getLeft());
         assertEquals(102, triple.getMiddle());
         assertEquals(103, triple.getRight());
diff --git a/core/src/test/java/com/alibaba/fastjson2/support/JSONObject1xTest.java b/core/src/test/java/com/alibaba/fastjson2/support/JSONObject1xTest.java
index 5f9b497c1..2fbeeef15 100644
--- a/core/src/test/java/com/alibaba/fastjson2/support/JSONObject1xTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/support/JSONObject1xTest.java
@@ -1,7 +1,7 @@
 package com.alibaba.fastjson2.support;
 
 import com.alibaba.fastjson.JSONObject;
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONArray;
 import com.alibaba.fastjson2.JSONB;
 import org.junit.jupiter.api.Test;
@@ -13,10 +13,10 @@ public class JSONObject1xTest {
     public void test_0() {
         JSONObject object = new JSONObject();
         assertEquals("{}"
-                , JSON.toJSONString(object));
+                , JsonMapper.toJsonString(object));
 
         assertEquals("{}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parse(
                                 JSONB.toBytes(object))));
     }
@@ -25,10 +25,10 @@ public class JSONObject1xTest {
     public void test_1() {
         JSONArray array = new JSONArray();
         assertEquals("[]"
-                , JSON.toJSONString(array));
+                , JsonMapper.toJsonString(array));
 
         assertEquals("[]"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         JSONB.parse(
                                 JSONB.toBytes(array))));
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/support/JacksonIgnoreTest.java b/core/src/test/java/com/alibaba/fastjson2/support/JacksonIgnoreTest.java
index 8e193943c..04aebe617 100644
--- a/core/src/test/java/com/alibaba/fastjson2/support/JacksonIgnoreTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/support/JacksonIgnoreTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.fasterxml.jackson.annotation.JsonIgnore;
 import org.junit.jupiter.api.Test;
 
@@ -9,9 +9,9 @@ import static junit.framework.TestCase.assertEquals;
 public class JacksonIgnoreTest {
     @Test
     public void test_0() throws Exception {
-        assertEquals("{}", JSON.toJSONString(new A("101")));
-        assertEquals("{}", JSON.toJSONString(new A1("101")));
-        assertEquals("{}", JSON.toJSONString(new A2("101")));
+        assertEquals("{}", JsonMapper.toJsonString(new A("101")));
+        assertEquals("{}", JsonMapper.toJsonString(new A1("101")));
+        assertEquals("{}", JsonMapper.toJsonString(new A2("101")));
     }
 
     public static class A {
diff --git a/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableListTest.java b/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableListTest.java
index 704f32cda..547a6169e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableListTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableListTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.guava;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.google.common.collect.ImmutableList;
 import org.junit.jupiter.api.Test;
 
@@ -9,13 +9,13 @@ import static junit.framework.TestCase.assertEquals;
 public class ImmutableListTest {
     @Test
     public void test_0() {
-        A a = JSON.parseObject("{\"values\":[1,2]}", A.class);
+        A a = JsonMapper.parseJsonObject("{\"values\":[1,2]}", A.class);
         assertEquals(2, a.values.size());
     }
 
     @Test
     public void test_1() {
-        B b = JSON.parseObject("{\"values\":[1,2]}", B.class);
+        B b = JsonMapper.parseJsonObject("{\"values\":[1,2]}", B.class);
         assertEquals(2, b.values.size());
         assertEquals("1", b.values.get(0));
         assertEquals("2", b.values.get(1));
diff --git a/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableMapTest.java b/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableMapTest.java
index b51c211e1..ff16e301e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableMapTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableMapTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.guava;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.google.common.collect.ImmutableMap;
 import org.junit.jupiter.api.Test;
 
@@ -9,7 +9,7 @@ import static junit.framework.TestCase.assertEquals;
 public class ImmutableMapTest {
     @Test
     public void test_0() {
-        A a = JSON.parseObject("{\"values\":{\"a\":1,\"b\":2}}", A.class);
+        A a = JsonMapper.parseJsonObject("{\"values\":{\"a\":1,\"b\":2}}", A.class);
         assertEquals(2, a.values.size());
         assertEquals(Integer.valueOf(1), a.values.get("a"));
         assertEquals(Integer.valueOf(2), a.values.get("b"));
@@ -17,7 +17,7 @@ public class ImmutableMapTest {
 
     @Test
     public void test_1() {
-        B b = JSON.parseObject("{\"values\":{\"a\":1,\"b\":2}}", B.class);
+        B b = JsonMapper.parseJsonObject("{\"values\":{\"a\":1,\"b\":2}}", B.class);
         assertEquals(2, b.values.size());
         assertEquals("1", b.values.get("a"));
         assertEquals("2", b.values.get("b"));
diff --git a/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableSetTest.java b/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableSetTest.java
index 527f89dfe..80e0cc7ba 100644
--- a/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableSetTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/support/guava/ImmutableSetTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.guava;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.google.common.collect.ImmutableSet;
 import org.junit.jupiter.api.Test;
 
@@ -9,13 +9,13 @@ import static junit.framework.TestCase.assertEquals;
 public class ImmutableSetTest {
     @Test
     public void test_0() {
-        A a = JSON.parseObject("{\"values\":[1,2]}", A.class);
+        A a = JsonMapper.parseJsonObject("{\"values\":[1,2]}", A.class);
         assertEquals(2, a.values.size());
     }
 
     @Test
     public void test_1() {
-        B b = JSON.parseObject("{\"values\":[1,2]}", B.class);
+        B b = JsonMapper.parseJsonObject("{\"values\":[1,2]}", B.class);
         assertEquals(2, b.values.size());
         assertEquals("1", b.values.iterator().next());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/support/sql/JdbcTimeTest.java b/core/src/test/java/com/alibaba/fastjson2/support/sql/JdbcTimeTest.java
index 89f2334f8..8024de15d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/support/sql/JdbcTimeTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/support/sql/JdbcTimeTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.sql;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONField;
@@ -32,13 +32,13 @@ public class JdbcTimeTest {
 
     @Test
     public void test_time() {
-        A a = JSON.parseObject("{\"value\":\"12:13:14\"}", A.class);
-        A a1 = JSON.parseObject("{\"value\":\"12:13:14\"}", A.class);
+        A a = JsonMapper.parseJsonObject("{\"value\":\"12:13:14\"}", A.class);
+        A a1 = JsonMapper.parseJsonObject("{\"value\":\"12:13:14\"}", A.class);
         assertEquals("12:13:14", a.value.toString());
         assertEquals("12:13:14", a1.value.toString());
 
-        assertEquals("{\"value\":\"12:13:14\"}", JSON.toJSONString(a));
-        assertEquals("{\"value\":null}", JSON.toJSONString(new A(), JSONWriter.Feature.WriteNulls));
+        assertEquals("{\"value\":\"12:13:14\"}", JsonMapper.toJsonString(a));
+        assertEquals("{\"value\":null}", JsonMapper.toJsonString(new A(), JSONWriter.Feature.WriteNulls));
 
         byte[] bytes = JSONB.toBytes(a);
         A a2 = JSONB.parseObject(bytes, A.class);
@@ -51,12 +51,12 @@ public class JdbcTimeTest {
 
         B b = new B();
         b.value = new Timestamp(millis);
-        String str = JSON.toJSONString(b);
-        B b1 = JSON.parseObject(str, B.class);
+        String str = JsonMapper.toJsonString(b);
+        B b1 = JsonMapper.parseJsonObject(str, B.class);
         assertEquals(b.value, b1.value);
 
         String str1 = "{\"value\":" + millis + "}";
-        B b2 = JSON.parseObject(str1, B.class);
+        B b2 = JsonMapper.parseJsonObject(str1, B.class);
         assertEquals(b.value, b2.value);
     }
 
@@ -73,18 +73,18 @@ public class JdbcTimeTest {
 
         B b = new B();
         b.value = ts;
-        String str = JSON.toJSONString(b);
-        B b1 = JSON.parseObject(str, B.class);
+        String str = JsonMapper.toJsonString(b);
+        B b1 = JsonMapper.parseJsonObject(str, B.class);
         assertEquals(b.value, b1.value);
 
-        String str2 = JSON.toJSONString(ts);
-        Timestamp ts1 = JSON.parseObject(str2, Timestamp.class);
+        String str2 = JsonMapper.toJsonString(ts);
+        Timestamp ts1 = JsonMapper.parseJsonObject(str2, Timestamp.class);
         assertEquals(now, ts1.toLocalDateTime());
         assertEquals(now.getNano(), ts1.toLocalDateTime().getNano());
 
 
-        String str3 = JSON.toJSONString(ts);
-        Timestamp ts2 = JSON.parseObject(str3, Timestamp.class);
+        String str3 = JsonMapper.toJsonString(ts);
+        Timestamp ts2 = JsonMapper.parseJsonObject(str3, Timestamp.class);
         assertEquals(now, ts2.toLocalDateTime());
         assertEquals(now.getNano(), ts2.toLocalDateTime().getNano());
     }
@@ -103,32 +103,32 @@ public class JdbcTimeTest {
 
         B b = new B();
         b.value = ts;
-        String str = JSON.toJSONString(b);
-        B b1 = JSON.parseObject(str, B.class);
+        String str = JsonMapper.toJsonString(b);
+        B b1 = JsonMapper.parseJsonObject(str, B.class);
         assertEquals(b.value, b1.value);
 
-        String str2 = JSON.toJSONString(ts);
-        Timestamp ts1 = JSON.parseObject(str2, Timestamp.class);
+        String str2 = JsonMapper.toJsonString(ts);
+        Timestamp ts1 = JsonMapper.parseJsonObject(str2, Timestamp.class);
         assertEquals(ts, ts1);
         assertEquals(ts.getNanos(), ts1.toLocalDateTime().getNano());
 
 
-        String str3 = JSON.toJSONString(ts);
-        Timestamp ts2 = JSON.parseObject(str3, Timestamp.class);
+        String str3 = JsonMapper.toJsonString(ts);
+        Timestamp ts2 = JsonMapper.parseJsonObject(str3, Timestamp.class);
         assertEquals(ts, ts2);
         assertEquals(ts.getNanos(), ts2.toLocalDateTime().getNano());
 
         C1 c1 = new C1();
         c1.value = ts;
-        JSON.toJSONString(c1);
+        JsonMapper.toJsonString(c1);
 
-        JSON.toJSONString(b, "iso8601");
+        JsonMapper.toJsonString(b, "iso8601");
     }
 
     @Test
     public void test_timestamp_1() {
         String str = "{\"value\":\"2012-12-01\"}";
-        C c = JSON.parseObject(str, C.class);
+        C c = JsonMapper.parseJsonObject(str, C.class);
         assertEquals(2012, c.value.toLocalDateTime().getYear());
         assertEquals(12, c.value.toLocalDateTime().getMonthValue());
     }
@@ -139,8 +139,8 @@ public class JdbcTimeTest {
 
         D d = new D();
         d.value = new java.sql.Date(millis);
-        String str = JSON.toJSONString(d);
-        D d1 = JSON.parseObject(str, D.class);
+        String str = JsonMapper.toJsonString(d);
+        D d1 = JsonMapper.parseJsonObject(str, D.class);
         assertEquals(d.value, d1.value);
 
         byte[] bytes = JSONB.toBytes(d);
@@ -152,7 +152,7 @@ public class JdbcTimeTest {
     @Test
     public void test_date_1() {
         String str = "{\"value\":\"2012-12-01\"}";
-        E e = JSON.parseObject(str, E.class);
+        E e = JsonMapper.parseJsonObject(str, E.class);
         assertEquals(2012, e.value.toLocalDate().getYear());
         assertEquals(12, e.value.toLocalDate().getMonthValue());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/time/DateTest3.java b/core/src/test/java/com/alibaba/fastjson2/time/DateTest3.java
index cd284f1a8..e80086437 100644
--- a/core/src/test/java/com/alibaba/fastjson2/time/DateTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/time/DateTest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.time;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -19,10 +19,10 @@ public class DateTest3 {
         bean.dates = new ArrayList<>();
         bean.dates.add(new Date(1644578127098L));
 
-        String str = JSON.toJSONString(bean);
+        String str = JsonMapper.toJsonString(bean);
         assertEquals("{\"dates\":[\"022022\"]}", str);
 
-        Bean bean1 = JSON.parseObject(str, Bean.class);
+        Bean bean1 = JsonMapper.parseJsonObject(str, Bean.class);
         assertEquals(1, bean1.dates.size());
         Calendar instance = Calendar.getInstance();
         instance.setTime(bean1.dates.get(0));
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1233.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1233.java
index 83e75013a..1e07d0677 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1233.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1233.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.annotation.JSONType;
 import org.junit.jupiter.api.Test;
@@ -16,10 +16,10 @@ import static org.junit.jupiter.api.Assertions.assertNotNull;
 public class Issue1233 {
     @Test
     public void test_for_issue() throws Exception {
-        JSONObject jsonObject = JSON.parseObject("{\"type\":\"floorV2\",\"templateId\":\"x123\"}");
+        JSONObject jsonObject = JsonMapper.parseJsonObject("{\"type\":\"floorV2\",\"templateId\":\"x123\"}");
 
-        JSON.mixIn(Area.class, AreaMixIn.class);
-        JSON.mixIn(FloorV2.class, FloorV2MixIn.class);
+        JsonMapper.addMixIn(Area.class, AreaMixIn.class);
+        JsonMapper.addMixIn(FloorV2.class, FloorV2MixIn.class);
 
         FloorV2 floorV2 = (FloorV2) jsonObject.toJavaObject(Area.class);
         assertNotNull(floorV2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1330_long.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1330_long.java
index 8ebfdfc6c..f14104f12 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1330_long.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1330_long.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONException;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertNotNull;
@@ -16,7 +15,7 @@ public class Issue1330_long {
     public void test_for_issue() throws Exception {
         Exception error = null;
         try {
-            JSON.parseObject("{\"value\":\"ABC\"}", Model.class);
+            JsonMapper.parseJsonObject("{\"value\":\"ABC\"}", Model.class);
         } catch (JSONException e) {
             error = e;
         }
@@ -28,7 +27,7 @@ public class Issue1330_long {
     public void test_for_issue_1() throws Exception {
         Exception error = null;
         try {
-            JSON.parseObject("{\"value\":[]}", Model.class);
+            JsonMapper.parseJsonObject("{\"value\":[]}", Model.class);
         } catch (JSONException e) {
             error = e;
         }
@@ -40,7 +39,7 @@ public class Issue1330_long {
     public void test_for_issue_2() throws Exception {
         Exception error = null;
         try {
-            JSON.parseObject("{\"value\":{}}", Model.class);
+            JsonMapper.parseJsonObject("{\"value\":{}}", Model.class);
         } catch (JSONException e) {
             error = e;
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1344.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1344.java
index 95cac6f2d..f77fcfd99 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1344.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1344.java
@@ -1,11 +1,9 @@
 package com.alibaba.fastjson2.v1issues;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import org.junit.jupiter.api.Test;
 
-import static junit.framework.TestCase.*;
-
 /**
  * Created by wenshao on 26/07/2017.
  */
@@ -13,8 +11,8 @@ public class Issue1344 {
     @Test
     public void test_for_issue() throws Exception {
         TestException testException = new TestException("aaa");
-        String json = JSON.toJSONString(testException);
-        TestException o = JSON.parseObject(json, TestException.class);
+        String json = JsonMapper.toJsonString(testException);
+        TestException o = JsonMapper.parseJsonObject(json, TestException.class);
         assertNull(o.getMessage());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_BrowserCompatible.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_BrowserCompatible.java
index e0959caa1..48e0a8010 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_BrowserCompatible.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_BrowserCompatible.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -18,7 +18,7 @@ public class BigDecimal_BrowserCompatible {
         map.put("id2", new BigDecimal("9223370018640066466"));
         map.put("id3", new BigDecimal("100"));
         assertEquals("{\"id1\":\"-9223370018640066466\",\"id2\":\"9223370018640066466\",\"id3\":100}",
-                JSON.toJSONString(map, JSONWriter.Feature.BrowserCompatible)
+                JsonMapper.toJsonString(map, JSONWriter.Feature.BrowserCompatible)
         );
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_field.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_field.java
index 2cdbdab48..a9fcbcb9b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_field.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_field.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -13,27 +13,27 @@ public class BigDecimal_field {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals("{\"value\":\"9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254741992L)));
 
         assertEquals("{\"value\":\"-9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254741992L)));
 
         assertEquals("{\"value\":9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254740990L)));
 
         assertEquals("{\"value\":-9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254740990L)));
 
         assertEquals("{\"value\":100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(100)));
 
         assertEquals("{\"value\":-100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-100)));
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_type.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_type.java
index 9d695ca42..568ab13fe 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_type.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigDecimal_type.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.jupiter.api.Test;
 
@@ -13,27 +13,27 @@ public class BigDecimal_type {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals("{\"value\":\"9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254741992L)));
 
         assertEquals("{\"value\":\"-9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254741992L)));
 
         assertEquals("{\"value\":9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254740990L)));
 
         assertEquals("{\"value\":-9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254740990L)));
 
         assertEquals("{\"value\":100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(100)));
 
         assertEquals("{\"value\":-100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-100)));
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigInteger_BrowserCompatible.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigInteger_BrowserCompatible.java
index 73c701d4d..8b409233a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigInteger_BrowserCompatible.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/BigInteger_BrowserCompatible.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -17,7 +17,7 @@ public class BigInteger_BrowserCompatible {
         map.put("id1", 9223370018640066466L);
         map.put("id2", new BigInteger("9223370018640066466"));
         assertEquals("{\"id1\":\"9223370018640066466\",\"id2\":\"9223370018640066466\"}",
-                JSON.toJSONString(map, JSONWriter.Feature.BrowserCompatible)
+                JsonMapper.toJsonString(map, JSONWriter.Feature.BrowserCompatible)
         );
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleNullTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleNullTest.java
index b318beede..431b30db8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleNullTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleNullTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import org.junit.jupiter.api.Test;
 
@@ -13,7 +13,7 @@ import static org.junit.jupiter.api.Assertions.assertNull;
 public class DoubleNullTest {
     @Test
     public void test_null() {
-        Model model = JSON.parseObject("{\"v1\":null,\"v2\":null}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null,\"v2\":null}", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -21,7 +21,7 @@ public class DoubleNullTest {
 
     @Test
     public void test_null_quote() {
-        Model model = JSON.parseObject("{\"v1\":\"null\",\"v2\":\"null\"}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\",\"v2\":\"null\"}", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -29,7 +29,7 @@ public class DoubleNullTest {
 
     @Test
     public void test_null_1() {
-        Model model = JSON.parseObject("{\"v1\":null ,\"v2\":null }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null ,\"v2\":null }", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -37,7 +37,7 @@ public class DoubleNullTest {
 
     @Test
     public void test_null_1_quote() {
-        Model model = JSON.parseObject("{\"v1\":\"null\" ,\"v2\":\"null\" }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\" ,\"v2\":\"null\" }", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -45,7 +45,7 @@ public class DoubleNullTest {
 
     @Test
     public void test_null_array() {
-        Model model = JSON.parseObject("[\"null\" ,\"null\"]", Model.class, JSONReader.Feature.SupportArrayToBean);
+        Model model = JsonMapper.parseJsonObject("[\"null\" ,\"null\"]", Model.class, JSONReader.Feature.SupportArrayToBean);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleNullTest_primitive.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleNullTest_primitive.java
index 79c8ea780..30215a85c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleNullTest_primitive.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleNullTest_primitive.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertNotNull;
 public class DoubleNullTest_primitive {
     @Test
     public void test_null() {
-        Model model = JSON.parseObject("{\"v1\":null,\"v2\":null}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null,\"v2\":null}", Model.class);
         assertNotNull(model);
         assertEquals(0D, model.v1);
         assertEquals(0D,model.v2);
@@ -20,7 +20,7 @@ public class DoubleNullTest_primitive {
 
     @Test
     public void test_null_1() {
-        Model model = JSON.parseObject("{\"v1\":null ,\"v2\":null }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null ,\"v2\":null }", Model.class);
         assertNotNull(model);
         assertEquals(0D,model.v1);
         assertEquals(0D,model.v2);
@@ -28,7 +28,7 @@ public class DoubleNullTest_primitive {
 
     @Test
     public void test_null_2() {
-        Model model = JSON.parseObject("{\"v1\":\"null\",\"v2\":\"null\" }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\",\"v2\":\"null\" }", Model.class);
         assertNotNull(model);
         assertEquals(0D,model.v1);
         assertEquals(0D,model.v2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest.java
index 35ebcc148..bf7ad644e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
 import org.junit.jupiter.api.Test;
 
@@ -16,8 +16,8 @@ public class DoubleTest {
         String json = "{\"v1\":-0.012671709,\"v2\":0.22676692048907365,\"v3\":0.13231707,\"v4\":0.80090785,\"v5\":0.6192943}";
         String json2 = "{\"v1\":\"-0.012671709\",\"v2\":\"0.22676692048907365\",\"v3\":\"0.13231707\",\"v4\":\"0.80090785\",\"v5\":\"0.6192943\"}";
 
-        Model m1 = JSON.parseObject(json, Model.class);
-        Model m2 = JSON.parseObject(json2, Model.class);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class);
 
         assertNotNull(m1);
         assertNotNull(m2);
@@ -40,8 +40,8 @@ public class DoubleTest {
         String json = "[-0.012671709,0.22676692048907365,0.13231707,0.80090785,0.6192943]";
         String json2 = "[\"-0.012671709\",\"0.22676692048907365\",\"0.13231707\",\"0.80090785\",\"0.6192943\"]";
 
-        Model m1 = JSON.parseObject(json, Model.class, Feature.SupportArrayToBean);
-        Model m2 = JSON.parseObject(json2, Model.class, Feature.SupportArrayToBean);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class, Feature.SupportArrayToBean);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class, Feature.SupportArrayToBean);
 
         assertNotNull(m1);
         assertNotNull(m2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest2_obj.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest2_obj.java
index dbbb294a9..b36f31560 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest2_obj.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest2_obj.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
 import org.junit.jupiter.api.Test;
 
@@ -16,8 +16,8 @@ public class DoubleTest2_obj {
         String json = "{\"v1\":-0.012671709,\"v2\":0.22676692048907365,\"v3\":0.13231707,\"v4\":0.80090785,\"v5\":0.6192943}";
         String json2 = "{\"v1\":\"-0.012671709\",\"v2\":\"0.22676692048907365\",\"v3\":\"0.13231707\",\"v4\":\"0.80090785\",\"v5\":\"0.6192943\"}";
 
-        Model m1 = JSON.parseObject(json, Model.class);
-        Model m2 = JSON.parseObject(json2, Model.class);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class);
 
         assertNotNull(m1);
         assertNotNull(m2);
@@ -40,8 +40,8 @@ public class DoubleTest2_obj {
         String json = "[-0.012671709,0.22676692048907365,0.13231707,0.80090785,0.6192943]";
         String json2 = "[\"-0.012671709\",\"0.22676692048907365\",\"0.13231707\",\"0.80090785\",\"0.6192943\"]";
 
-        Model m1 = JSON.parseObject(json, Model.class, Feature.SupportArrayToBean);
-        Model m2 = JSON.parseObject(json2, Model.class, Feature.SupportArrayToBean);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class, Feature.SupportArrayToBean);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class, Feature.SupportArrayToBean);
 
         assertNotNull(m1);
         assertNotNull(m2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest3_random.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest3_random.java
index e1dbb6f2a..867c5da80 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest3_random.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/DoubleTest3_random.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -16,9 +16,9 @@ public class DoubleTest3_random {
     @Test
     public void test_extract() throws Exception {
         double val = 7.754693899073573E-4;
-        String str = JSON.toJSONString(new Model(val));
+        String str = JsonMapper.toJsonString(new Model(val));
         System.out.println(str);
-        Model m = JSON.parseObject(str, Model.class);
+        Model m = JsonMapper.parseJsonObject(str, Model.class);
 
         assertEquals(val, m.value);
     }
@@ -27,16 +27,16 @@ public class DoubleTest3_random {
     public void test_extract_1() throws Exception {
         double val = 0.21474836515489015;
 
-        String str = JSON.toJSONString(new Model(val));
+        String str = JsonMapper.toJsonString(new Model(val));
         assertEquals("{\"value\":0.21474836515489015}", str);
 
         {
-            Model m = JSON.parseObject(str, Model.class);
+            Model m = JsonMapper.parseJsonObject(str, Model.class);
             assertEquals(val, m.value);
         }
 
         {
-            Model m = JSON.parseObject(str.getBytes(StandardCharsets.UTF_8), Model.class);
+            Model m = JsonMapper.parseJsonObject(str.getBytes(StandardCharsets.UTF_8), Model.class);
             assertEquals(val, m.value);
         }
     }
@@ -48,8 +48,8 @@ public class DoubleTest3_random {
         for (int i = 0; i < 1000 * 1000 * 1; ++i) {
             double val = rand.nextDouble();
 
-            String str = JSON.toJSONString(new Model(val));
-            Model m = JSON.parseObject(str, Model.class);
+            String str = JsonMapper.toJsonString(new Model(val));
+            Model m = JsonMapper.parseJsonObject(str, Model.class);
 
             assertEquals(val, m.value);
         }
@@ -62,8 +62,8 @@ public class DoubleTest3_random {
         for (int i = 0; i < 1000 * 1000 * 1; ++i) {
             double val = rand.nextDouble();
 
-            String str = JSON.toJSONString(new Model(val), JSONWriter.Feature.BeanToArray);
-            Model m = JSON.parseObject(str, Model.class, Feature.SupportArrayToBean);
+            String str = JsonMapper.toJsonString(new Model(val), JSONWriter.Feature.BeanToArray);
+            Model m = JsonMapper.parseJsonObject(str, Model.class, Feature.SupportArrayToBean);
 
             assertEquals(val, m.value);
         }
@@ -76,8 +76,8 @@ public class DoubleTest3_random {
         for (int i = 0; i < 1000 * 1000 * 1; ++i) {
             double val = rand.nextDouble();
 
-            String str = JSON.toJSONString(Collections.singletonMap("val", val));
-            double val2 = JSON.parseObject(str).getDoubleValue("val");
+            String str = JsonMapper.toJsonString(Collections.singletonMap("val", val));
+            double val2 = JsonMapper.parseJsonObject(str).getDoubleValue("val");
 
             assertEquals(val, val2);
         }
@@ -92,8 +92,8 @@ public class DoubleTest3_random {
 
             HashMap map = new HashMap();
             map.put("val", val);
-            String str = JSON.toJSONString(map);
-            double val2 = JSON.parseObject(str).getDoubleValue("val");
+            String str = JsonMapper.toJsonString(map);
+            double val2 = JsonMapper.parseJsonObject(str).getDoubleValue("val");
 
             assertEquals(val, val2);
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatNullTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatNullTest.java
index 53f1d8c8a..9ab1bc0b0 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatNullTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatNullTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
 import org.junit.jupiter.api.Test;
 
@@ -15,7 +15,7 @@ import static org.junit.jupiter.api.Assertions.assertNull;
 public class FloatNullTest {
     @Test
     public void test_null() {
-        Model model = JSON.parseObject("{\"v1\":null,\"v2\":null}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null,\"v2\":null}", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -23,7 +23,7 @@ public class FloatNullTest {
 
     @Test
     public void test_null_quote() {
-        Model model = JSON.parseObject("{\"v1\":\"null\",\"v2\":\"null\"}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\",\"v2\":\"null\"}", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -31,7 +31,7 @@ public class FloatNullTest {
 
     @Test
     public void test_null_1() {
-        Model model = JSON.parseObject("{\"v1\":null ,\"v2\":null }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null ,\"v2\":null }", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -39,7 +39,7 @@ public class FloatNullTest {
 
     @Test
     public void test_null_1_quote() {
-        Model model = JSON.parseObject("{\"v1\":\"null\" ,\"v2\":\"null\" }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\" ,\"v2\":\"null\" }", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -47,7 +47,7 @@ public class FloatNullTest {
 
     @Test
     public void test_null_array() {
-        Model model = JSON.parseObject("[\"null\" ,\"null\"]", Model.class, Feature.SupportArrayToBean);
+        Model model = JsonMapper.parseJsonObject("[\"null\" ,\"null\"]", Model.class, Feature.SupportArrayToBean);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatNullTest_primitive.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatNullTest_primitive.java
index 1a302e990..5a5e5c838 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatNullTest_primitive.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatNullTest_primitive.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertNotNull;
 public class FloatNullTest_primitive {
     @Test
     public void test_null() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null,\"v2\":null}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null,\"v2\":null}", Model.class);
         assertNotNull(model);
         assertEquals(0F, model.v1);
         assertEquals(0F,model.v2);
@@ -20,7 +20,7 @@ public class FloatNullTest_primitive {
 
     @Test
     public void test_null_1() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null ,\"v2\":null }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null ,\"v2\":null }", Model.class);
         assertNotNull(model);
         assertEquals(0F,model.v1);
         assertEquals(0F,model.v2);
@@ -28,7 +28,7 @@ public class FloatNullTest_primitive {
 
     @Test
     public void test_null_2() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":\"null\",\"v2\":\"null\" }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\",\"v2\":\"null\" }", Model.class);
         assertNotNull(model);
         assertEquals(0F,model.v1);
         assertEquals(0F,model.v2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest.java
index 6a7fa7ce8..940fcc135 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
 import org.junit.jupiter.api.Test;
 
@@ -16,8 +16,8 @@ public class FloatTest {
         String json = "{\"v1\":-0.012671709,\"v2\":0.6042485,\"v3\":0.13231707,\"v4\":0.80090785,\"v5\":0.6192943}";
         String json2 = "{\"v1\":\"-0.012671709\",\"v2\":\"0.6042485\",\"v3\":\"0.13231707\",\"v4\":\"0.80090785\",\"v5\":\"0.6192943\"}";
 
-        Model m1 = JSON.parseObject(json, Model.class);
-        Model m2 = JSON.parseObject(json2, Model.class);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class);
 
         assertNotNull(m1);
         assertNotNull(m2);
@@ -40,8 +40,8 @@ public class FloatTest {
         String json = "[-0.012671709,0.6042485,0.13231707,0.80090785,0.6192943]";
         String json2 = "[\"-0.012671709\",\"0.6042485\",\"0.13231707\",\"0.80090785\",\"0.6192943\"]";
 
-        Model m1 = JSON.parseObject(json, Model.class, Feature.SupportArrayToBean);
-        Model m2 = JSON.parseObject(json2, Model.class, Feature.SupportArrayToBean);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class, Feature.SupportArrayToBean);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class, Feature.SupportArrayToBean);
 
         assertNotNull(m1);
         assertNotNull(m2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest2_obj.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest2_obj.java
index 741833577..8f6a76965 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest2_obj.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest2_obj.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
 import org.junit.jupiter.api.Test;
 
@@ -16,8 +16,8 @@ public class FloatTest2_obj {
         String json = "{\"v1\":-0.012671709,\"v2\":0.6042485,\"v3\":0.13231707,\"v4\":0.80090785,\"v5\":0.6192943}";
         String json2 = "{\"v1\":\"-0.012671709\",\"v2\":\"0.6042485\",\"v3\":\"0.13231707\",\"v4\":\"0.80090785\",\"v5\":\"0.6192943\"}";
 
-        Model m1 = JSON.parseObject(json, Model.class);
-        Model m2 = JSON.parseObject(json2, Model.class);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class);
 
         assertNotNull(m1);
         assertNotNull(m2);
@@ -40,8 +40,8 @@ public class FloatTest2_obj {
         String json = "[-0.012671709,0.6042485,0.13231707,0.80090785,0.6192943]";
         String json2 = "[\"-0.012671709\",\"0.6042485\",\"0.13231707\",\"0.80090785\",\"0.6192943\"]";
 
-        Model m1 = JSON.parseObject(json, Model.class, Feature.SupportArrayToBean);
-        Model m2 = JSON.parseObject(json2, Model.class, Feature.SupportArrayToBean);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class, Feature.SupportArrayToBean);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class, Feature.SupportArrayToBean);
 
         assertNotNull(m1);
         assertNotNull(m2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest3_array_random.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest3_array_random.java
index 8d4f5cc94..9e2109bea 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest3_array_random.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest3_array_random.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
-import com.alibaba.fastjson.serializer.SerializerFeature;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -18,8 +17,8 @@ public class FloatTest3_array_random {
         for (int i = 0; i < 1000 * 1000 * 1; ++i) {
             float val = rand.nextFloat();
 
-            String str = JSON.toJSONString(new Model(new float[]{val}));
-            Model m = JSON.parseObject(str, Model.class);
+            String str = JsonMapper.toJsonString(new Model(new float[]{val}));
+            Model m = JsonMapper.parseJsonObject(str, Model.class);
 
             assertEquals(val, m.value[0]);
         }
@@ -32,8 +31,8 @@ public class FloatTest3_array_random {
         for (int i = 0; i < 1000 * 1000 * 10; ++i) {
             float val = rand.nextFloat();
 
-            String str = JSON.toJSONString(new Model(new float[]{val}), JSONWriter.Feature.BeanToArray);
-            Model m = JSON.parseObject(str, Model.class, Feature.SupportArrayToBean);
+            String str = JsonMapper.toJsonString(new Model(new float[]{val}), JSONWriter.Feature.BeanToArray);
+            Model m = JsonMapper.parseJsonObject(str, Model.class, Feature.SupportArrayToBean);
 
             assertEquals(val, m.value[0]);
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest3_random.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest3_random.java
index 028a0ff22..e94b408be 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest3_random.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/FloatTest3_random.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
-import com.alibaba.fastjson.serializer.SerializerFeature;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -20,8 +19,8 @@ public class FloatTest3_random {
         for (int i = 0; i < 1000 * 1000 * 1; ++i) {
             float val = rand.nextFloat();
 
-            String str = JSON.toJSONString(new Model(val));
-            Model m = JSON.parseObject(str, Model.class);
+            String str = JsonMapper.toJsonString(new Model(val));
+            Model m = JsonMapper.parseJsonObject(str, Model.class);
 
             assertEquals(val, m.value);
         }
@@ -34,8 +33,8 @@ public class FloatTest3_random {
         for (int i = 0; i < 1000 * 1000 * 1; ++i) {
             float val = rand.nextFloat();
 
-            String str = JSON.toJSONString(new Model(val), JSONWriter.Feature.BeanToArray);
-            Model m = JSON.parseObject(str, Model.class, Feature.SupportArrayToBean);
+            String str = JsonMapper.toJsonString(new Model(val), JSONWriter.Feature.BeanToArray);
+            Model m = JsonMapper.parseJsonObject(str, Model.class, Feature.SupportArrayToBean);
 
             assertEquals(val, m.value);
         }
@@ -48,8 +47,8 @@ public class FloatTest3_random {
         for (int i = 0; i < 1000 * 1000 * 1; ++i) {
             float val = rand.nextFloat();
 
-            String str = JSON.toJSONString(Collections.singletonMap("val", val));
-            float val2 = JSON.parseObject(str).getFloatValue("val");
+            String str = JsonMapper.toJsonString(Collections.singletonMap("val", val));
+            float val2 = JsonMapper.parseJsonObject(str).getFloatValue("val");
 
             assertEquals(val, val2);
         }
@@ -64,8 +63,8 @@ public class FloatTest3_random {
 
             HashMap map = new HashMap();
             map.put("val", val);
-            String str = JSON.toJSONString(map);
-            float val2 = JSON.parseObject(str).getFloatValue("val");
+            String str = JsonMapper.toJsonString(map);
+            float val2 = JsonMapper.parseJsonObject(str).getFloatValue("val");
 
             assertEquals(val, val2);
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntNullTest_primitive.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntNullTest_primitive.java
index 54e0bd85e..c9cc6de7a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntNullTest_primitive.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntNullTest_primitive.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertNotNull;
 public class IntNullTest_primitive {
     @Test
     public void test_null() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null,\"v2\":null}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null,\"v2\":null}", Model.class);
         assertNotNull(model);
         assertEquals(0, model.v1);
         assertEquals(0,model.v2);
@@ -20,7 +20,7 @@ public class IntNullTest_primitive {
 
     @Test
     public void test_null_1() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null ,\"v2\":null }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null ,\"v2\":null }", Model.class);
         assertNotNull(model);
         assertEquals(0,model.v1);
         assertEquals(0,model.v2);
@@ -28,7 +28,7 @@ public class IntNullTest_primitive {
 
     @Test
     public void test_null_2() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":\"null\",\"v2\":\"null\" }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\",\"v2\":\"null\" }", Model.class);
         assertNotNull(model);
         assertEquals(0,model.v1);
         assertEquals(0,model.v2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntTest.java
index f27b6d649..d9ceced4c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -13,8 +13,8 @@ public class IntTest {
     @Test
     public void test_array() throws Exception {
         int[] values = new int[] {Integer.MIN_VALUE, -1, 0, 1, Integer.MAX_VALUE};
-        String text = JSON.toJSONString(values);
-        long[] values_2 = JSON.parseObject(text, long[].class);
+        String text = JsonMapper.toJsonString(values);
+        long[] values_2 = JsonMapper.parseJsonObject(text, long[].class);
         assertEquals(values_2.length, values.length);
         for (int i = 0; i < values.length; ++i) {
             assertEquals(values[i], values_2[i]);
@@ -29,8 +29,8 @@ public class IntTest {
             map.put(Integer.toString(i), values[i]);
         }
 
-        String text = JSON.toJSONString(map);
-        JSONObject obj = JSON.parseObject(text);
+        String text = JsonMapper.toJsonString(map);
+        JSONObject obj = JsonMapper.parseJsonObject(text);
         for (int i = 0; i < values.length; ++i) {
             assertEquals(values[i], ((Number) obj.get(Integer.toString(i))).intValue());
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntegerNullTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntegerNullTest.java
index 282c17c8e..8265105b5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntegerNullTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/IntegerNullTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
 import org.junit.jupiter.api.Test;
 
@@ -15,7 +15,7 @@ import static org.junit.jupiter.api.Assertions.assertNull;
 public class IntegerNullTest {
     @Test
     public void test_null() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null,\"v2\":null}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null,\"v2\":null}", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -23,7 +23,7 @@ public class IntegerNullTest {
 
     @Test
     public void test_null_quote() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":\"null\",\"v2\":\"null\"}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\",\"v2\":\"null\"}", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -31,7 +31,7 @@ public class IntegerNullTest {
 
     @Test
     public void test_null_1() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null ,\"v2\":null }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null ,\"v2\":null }", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -39,7 +39,7 @@ public class IntegerNullTest {
 
     @Test
     public void test_null_1_quote() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":\"null\" ,\"v2\":\"null\" }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\" ,\"v2\":\"null\" }", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -47,7 +47,7 @@ public class IntegerNullTest {
 
     @Test
     public void test_null_array() throws Exception {
-        Model model = JSON.parseObject("[\"null\" ,\"null\"]", Model.class, Feature.SupportArrayToBean);
+        Model model = JsonMapper.parseJsonObject("[\"null\" ,\"null\"]", Model.class, Feature.SupportArrayToBean);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongNullTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongNullTest.java
index e0ebb9ac8..9460feb1e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongNullTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongNullTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader.Feature;
 import org.junit.jupiter.api.Test;
 
@@ -15,7 +15,7 @@ import static org.junit.jupiter.api.Assertions.assertNull;
 public class LongNullTest {
     @Test
     public void test_null() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null,\"v2\":null}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null,\"v2\":null}", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -23,7 +23,7 @@ public class LongNullTest {
 
     @Test
     public void test_null_quote() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":\"null\",\"v2\":\"null\"}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\",\"v2\":\"null\"}", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -31,7 +31,7 @@ public class LongNullTest {
 
     @Test
     public void test_null_1() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null ,\"v2\":null }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null ,\"v2\":null }", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -39,7 +39,7 @@ public class LongNullTest {
 
     @Test
     public void test_null_1_quote() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":\"null\" ,\"v2\":\"null\" }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\" ,\"v2\":\"null\" }", Model.class);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
@@ -47,7 +47,7 @@ public class LongNullTest {
 
     @Test
     public void test_null_array() throws Exception {
-        Model model = JSON.parseObject("[\"null\" ,\"null\"]", Model.class, Feature.SupportArrayToBean);
+        Model model = JsonMapper.parseJsonObject("[\"null\" ,\"null\"]", Model.class, Feature.SupportArrayToBean);
         assertNotNull(model);
         assertNull(model.v1);
         assertNull(model.v2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongNullTest_primitive.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongNullTest_primitive.java
index 885faff79..179f195af 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongNullTest_primitive.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongNullTest_primitive.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertNotNull;
 public class LongNullTest_primitive {
     @Test
     public void test_null() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null,\"v2\":null}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null,\"v2\":null}", Model.class);
         assertNotNull(model);
         assertEquals(0, model.v1);
         assertEquals(0,model.v2);
@@ -20,7 +20,7 @@ public class LongNullTest_primitive {
 
     @Test
     public void test_null_1() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":null ,\"v2\":null }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":null ,\"v2\":null }", Model.class);
         assertNotNull(model);
         assertEquals(0,model.v1);
         assertEquals(0,model.v2);
@@ -28,7 +28,7 @@ public class LongNullTest_primitive {
 
     @Test
     public void test_null_2() throws Exception {
-        Model model = JSON.parseObject("{\"v1\":\"null\",\"v2\":\"null\" }", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"v1\":\"null\",\"v2\":\"null\" }", Model.class);
         assertNotNull(model);
         assertEquals(0,model.v1);
         assertEquals(0,model.v2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest.java
index 39ee413cb..4d80e23f5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -13,8 +13,8 @@ public class LongTest {
     @Test
     public void test_array() throws Exception {
         long[] values = new long[] {Long.MIN_VALUE, -1, 0, 1, Long.MAX_VALUE};
-        String text = JSON.toJSONString(values);
-        long[] values_2 = JSON.parseObject(text, long[].class);
+        String text = JsonMapper.toJsonString(values);
+        long[] values_2 = JsonMapper.parseJsonObject(text, long[].class);
         assertEquals(values_2.length, values.length);
         for (int i = 0; i < values.length; ++i) {
             assertEquals(values[i], values_2[i]);
@@ -29,8 +29,8 @@ public class LongTest {
             map.put(Long.toString(i), values[i]);
         }
 
-        String text = JSON.toJSONString(map);
-        JSONObject obj = JSON.parseObject(text);
+        String text = JsonMapper.toJsonString(map);
+        JSONObject obj = JsonMapper.parseJsonObject(text);
         for (int i = 0; i < values.length; ++i) {
             assertEquals(values[i], ((Number) obj.get(Long.toString(i))).longValue());
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest2.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest2.java
index d76dde0b7..89c23c401 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest2.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
-import com.alibaba.fastjson2.JSONReader.Feature;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -16,8 +15,8 @@ public class LongTest2 {
         String json = "{\"v1\":-1883391953414482124,\"v2\":-3019416596934963650,\"v3\":6497525620823745793,\"v4\":2136224289077142499,\"v5\":-2090575024006307745}";
         String json2 = "{\"v1\":\"-1883391953414482124\",\"v2\":\"-3019416596934963650\",\"v3\":\"6497525620823745793\",\"v4\":\"2136224289077142499\",\"v5\":\"-2090575024006307745\"}";
 
-        Model m1 = JSON.parseObject(json, Model.class);
-        Model m2 = JSON.parseObject(json2, Model.class);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class);
 
         assertNotNull(m1);
         assertNotNull(m2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest2_obj.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest2_obj.java
index c85ebe991..a3a037295 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest2_obj.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest2_obj.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
-import com.alibaba.fastjson2.JSONReader.Feature;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.io.StringReader;
@@ -18,8 +17,8 @@ public class LongTest2_obj {
         String json = "{\"v1\":-1883391953414482124,\"v2\":-3019416596934963650,\"v3\":6497525620823745793,\"v4\":2136224289077142499,\"v5\":-2090575024006307745}";
         String json2 = "{\"v1\":\"-1883391953414482124\",\"v2\":\"-3019416596934963650\",\"v3\":\"6497525620823745793\",\"v4\":\"2136224289077142499\",\"v5\":\"-2090575024006307745\"}";
 
-        Model m1 = JSON.parseObject(json, Model.class);
-        Model m2 = JSON.parseObject(json2, Model.class);
+        Model m1 = JsonMapper.parseJsonObject(json, Model.class);
+        Model m2 = JsonMapper.parseJsonObject(json2, Model.class);
 
         assertNotNull(m1);
         assertNotNull(m2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest_browserCompatible.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest_browserCompatible.java
index 263e6267e..0979ef798 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest_browserCompatible.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/basicType/LongTest_browserCompatible.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.basicType;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -14,8 +14,8 @@ public class LongTest_browserCompatible {
     @Test
     public void test_array() throws Exception {
         long[] values = new long[] {Long.MIN_VALUE, -1, 0, 1, Long.MAX_VALUE};
-        String text = JSON.toJSONString(values, JSONWriter.Feature.BrowserCompatible);
-        long[] values_2 = JSON.parseObject(text, long[].class);
+        String text = JsonMapper.toJsonString(values, JSONWriter.Feature.BrowserCompatible);
+        long[] values_2 = JsonMapper.parseJsonObject(text, long[].class);
         assertEquals(values_2.length, values.length);
         for (int i = 0; i < values.length; ++i) {
             assertEquals(values[i], values_2[i]);
@@ -60,8 +60,8 @@ public class LongTest_browserCompatible {
             map.put(Long.toString(i), values[i]);
         }
 
-        String text = JSON.toJSONString(map, JSONWriter.Feature.BrowserCompatible);
-        JSONObject obj = JSON.parseObject(text);
+        String text = JsonMapper.toJsonString(map, JSONWriter.Feature.BrowserCompatible);
+        JSONObject obj = JsonMapper.parseJsonObject(text);
         for (int i = 0; i < values.length; ++i) {
             assertEquals(values[i], ((Number) obj.getLong(Long.toString(i))).longValue());
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest0.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest0.java
index 7d44efa50..794966fdc 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest0.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest0.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.Assert;
 import org.junit.jupiter.api.Test;
@@ -9,7 +9,7 @@ public class BuilderTest0 {
 
     @Test
     public void test_0() throws Exception {
-        VO vo = JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
 
         Assert.assertEquals(12304, vo.getId());
         Assert.assertEquals("ljw", vo.getName());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest0_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest0_private.java
index 7f00a3dd4..37a42013a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest0_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest0_private.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.Assert;
 import org.junit.jupiter.api.Test;
@@ -9,7 +9,7 @@ public class BuilderTest0_private {
 
     @Test
     public void test_0() throws Exception {
-        VO vo = JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
 
         Assert.assertEquals(12304, vo.getId());
         Assert.assertEquals("ljw", vo.getName());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest1.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest1.java
index 05d2f5bee..6dc2f4053 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest1.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest1.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.Assert;
 import org.junit.jupiter.api.Test;
@@ -9,7 +9,7 @@ public class BuilderTest1 {
 
     @Test
     public void test_create() throws Exception {
-        VO vo = JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
 
         Assert.assertEquals(12304, vo.getId());
         Assert.assertEquals("ljw", vo.getName());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest1_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest1_private.java
index 59edd6462..278b0d573 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest1_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest1_private.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.jupiter.api.Test;
 
@@ -10,7 +10,7 @@ public class BuilderTest1_private {
 
     @Test
     public void test_create() throws Exception {
-        VO vo = JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
 
         assertEquals(12304, vo.getId());
         assertEquals("ljw", vo.getName());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest2.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest2.java
index 85ab18e92..9b85e0092 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest2.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONPOJOBuilder;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.jupiter.api.Test;
@@ -11,7 +11,7 @@ public class BuilderTest2 {
 
     @Test
     public void test_create() throws Exception {
-        VO vo = JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
 
         assertEquals(12304, vo.getId());
         assertEquals("ljw", vo.getName());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest2_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest2_private.java
index 6182101d5..aa5b91fd9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest2_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest2_private.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONPOJOBuilder;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.jupiter.api.Test;
@@ -11,7 +11,7 @@ public class BuilderTest2_private {
 
     @Test
     public void test_create() throws Exception {
-        VO vo = JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
 
         assertEquals(12304, vo.getId());
         assertEquals("ljw", vo.getName());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest3.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest3.java
index 1fca66e05..edb43cab6 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest3.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONPOJOBuilder;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.jupiter.api.Test;
@@ -11,7 +11,7 @@ public class BuilderTest3 {
 
     @Test
     public void test_create() throws Exception {
-        VO vo = JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
 
         assertEquals(12304, vo.getId());
         assertEquals("ljw", vo.getName());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest3_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest3_private.java
index 2c02cdbcf..ec504ca56 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest3_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest3_private.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONField;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.jupiter.api.Test;
@@ -11,7 +11,7 @@ public class BuilderTest3_private {
 
     @Test
     public void test_create() throws Exception {
-        VO vo = JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+        VO vo = JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
 
         assertEquals(12304, vo.getId());
         assertEquals("ljw", vo.getName());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest_error.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest_error.java
index 6c9b4789c..9f9f70001 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest_error.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest_error.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.JSONException;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.jupiter.api.Test;
@@ -13,7 +13,7 @@ public class BuilderTest_error {
     public void test_0() throws Exception {
         Exception error = null;
         try {
-            JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+            JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
         } catch (JSONException | com.alibaba.fastjson2.JSONException ex) {
             error = ex;
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest_error_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest_error_private.java
index 8978d384b..fb59065d9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest_error_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/builder/BuilderTest_error_private.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.builder;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.JSONException;
 import com.alibaba.fastjson.annotation.JSONType;
 import org.junit.jupiter.api.Test;
@@ -13,7 +13,7 @@ public class BuilderTest_error_private {
     public void test_0() throws Exception {
         Exception error = null;
         try {
-            JSON.parseObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
+            JsonMapper.parseJsonObject("{\"id\":12304,\"name\":\"ljw\"}", VO.class);
         } catch (JSONException | com.alibaba.fastjson2.JSONException ex) {
             error = ex;
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/date/DateFieldTest5.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/date/DateFieldTest5.java
index 208d9ba10..8cc1d0d72 100755
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/date/DateFieldTest5.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/date/DateFieldTest5.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.date;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONField;
 import com.alibaba.fastjson.serializer.SerializeConfig;
 import com.alibaba.fastjson2.JSONWriter;
@@ -17,7 +17,7 @@ public class DateFieldTest5 {
         V0 v = new V0();
         v.setValue(new Date());
 
-        String text = JSON.toJSONString(v);
+        String text = JsonMapper.toJsonString(v);
 
         assertEquals("{\"value\":" + v.getValue().getTime() + "}", text);
     }
@@ -27,7 +27,7 @@ public class DateFieldTest5 {
         V0 v = new V0();
         v.setValue(new Date());
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls);
         assertEquals("{\"value\":" + v.getValue().getTime() + "}", text);
     }
 
@@ -39,10 +39,10 @@ public class DateFieldTest5 {
         SerializeConfig mapping = new SerializeConfig();
         mapping.setAsmEnable(true);
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls);
         assertEquals("{\"value\":null}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(v1.getValue(), v.getValue());
     }
@@ -51,10 +51,10 @@ public class DateFieldTest5 {
     public void test_codec_null_1() {
         V0 v = new V0();
 
-        String text = JSON.toJSONString(v, JSONWriter.Feature.WriteNulls);
+        String text = JsonMapper.toJsonString(v, JSONWriter.Feature.WriteNulls);
         assertEquals("{\"value\":null}", text);
 
-        V0 v1 = JSON.parseObject(text, V0.class);
+        V0 v1 = JsonMapper.parseJsonObject(text, V0.class);
 
         assertEquals(null, v1.getValue());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/FeatureCollectionTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/FeatureCollectionTest.java
index bb53634cd..29f505866 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/FeatureCollectionTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/FeatureCollectionTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.FeatureCollection;
 import com.alibaba.fastjson.support.geo.Geometry;
 import org.junit.jupiter.api.Test;
@@ -59,12 +59,12 @@ public class FeatureCollectionTest {
                 "    }]\n" +
                 "}\n";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(FeatureCollection.class, geometry.getClass());
 
-        assertEquals("{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"prop0\":\"value0\"},\"geometry\":{\"type\":\"Point\",\"coordinates\":[102.0,0.5]}},{\"type\":\"Feature\",\"properties\":{\"prop1\":\"0.0\",\"prop0\":\"value0\"},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[102.0,0.0],[103.0,1.0],[104.0,0.0],[105.0,1.0]]}},{\"type\":\"Feature\",\"properties\":{\"prop1\":\"{\\\"this\\\":\\\"that\\\"}\",\"prop0\":\"value0\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[100.0,0.0],[101.0,0.0],[101.0,1.0],[100.0,1.0],[100.0,0.0]]]}}]}", JSON.toJSONString(geometry));
+        assertEquals("{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"prop0\":\"value0\"},\"geometry\":{\"type\":\"Point\",\"coordinates\":[102.0,0.5]}},{\"type\":\"Feature\",\"properties\":{\"prop1\":\"0.0\",\"prop0\":\"value0\"},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[102.0,0.0],[103.0,1.0],[104.0,0.0],[105.0,1.0]]}},{\"type\":\"Feature\",\"properties\":{\"prop1\":\"{\\\"this\\\":\\\"that\\\"}\",\"prop0\":\"value0\"},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[100.0,0.0],[101.0,0.0],[101.0,1.0],[100.0,1.0],[100.0,0.0]]]}}]}", JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/FeatureTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/FeatureTest.java
index cfe06a071..1614b2437 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/FeatureTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/FeatureTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.Feature;
 import com.alibaba.fastjson.support.geo.Geometry;
 import org.junit.jupiter.api.Test;
@@ -26,13 +26,13 @@ public class FeatureTest {
                 "    }\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(Feature.class, geometry.getClass());
 
-        assertEquals("{\"type\":\"Feature\",\"bbox\":[-10.0,-10.0,10.0,10.0],\"properties\":{},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-10.0,-10.0],[10.0,-10.0],[10.0,10.0],[-10.0,-10.0]]]}}", JSON.toJSONString(geometry));
+        assertEquals("{\"type\":\"Feature\",\"bbox\":[-10.0,-10.0,10.0,10.0],\"properties\":{},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-10.0,-10.0],[10.0,-10.0],[10.0,10.0],[-10.0,-10.0]]]}}", JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 
     @Test
@@ -53,12 +53,12 @@ public class FeatureTest {
                 "    }\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(Feature.class, geometry.getClass());
 
-        assertEquals("{\"type\":\"Feature\",\"id\":\"f2\",\"properties\":{},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-10.0,-10.0],[10.0,-10.0],[10.0,10.0],[-10.0,-10.0]]]}}", JSON.toJSONString(geometry));
+        assertEquals("{\"type\":\"Feature\",\"id\":\"f2\",\"properties\":{},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[-10.0,-10.0],[10.0,-10.0],[10.0,10.0],[-10.0,-10.0]]]}}", JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/GeometryCollectionTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/GeometryCollectionTest.java
index c10bf78ed..573e0cd0d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/GeometryCollectionTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/GeometryCollectionTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.Geometry;
 import com.alibaba.fastjson.support.geo.GeometryCollection;
 import org.junit.jupiter.api.Test;
@@ -24,14 +24,14 @@ public class GeometryCollectionTest {
                 "    }]\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(GeometryCollection.class, geometry.getClass());
 
         assertEquals(
                 "{\"type\":\"GeometryCollection\",\"geometries\":[{\"type\":\"Point\",\"coordinates\":[100.0,0.0]},{\"type\":\"LineString\",\"coordinates\":[[101.0,0.0],[102.0,1.0]]}]}"
-                , JSON.toJSONString(geometry));
+                , JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/LineStringTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/LineStringTest.java
index 609c08f73..fc14e1ecd 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/LineStringTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/LineStringTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.Geometry;
 import com.alibaba.fastjson.support.geo.LineString;
 import org.junit.jupiter.api.Test;
@@ -18,12 +18,12 @@ public class LineStringTest {
                 "    ]\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(LineString.class, geometry.getClass());
 
-        assertEquals("{\"type\":\"LineString\",\"coordinates\":[[100.0,0.0],[101.0,1.0]]}", JSON.toJSONString(geometry));
+        assertEquals("{\"type\":\"LineString\",\"coordinates\":[[100.0,0.0],[101.0,1.0]]}", JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiLineStringTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiLineStringTest.java
index 57cbec5de..34f950f58 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiLineStringTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiLineStringTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.Geometry;
 import com.alibaba.fastjson.support.geo.MultiLineString;
 import org.junit.jupiter.api.Test;
@@ -24,12 +24,12 @@ public class MultiLineStringTest {
                 "    ]\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(MultiLineString.class, geometry.getClass());
 
-        assertEquals("{\"type\":\"MultiLineString\",\"coordinates\":[[[100.0,0.0],[101.0,1.0]],[[102.0,2.0],[103.0,3.0]]]}", JSON.toJSONString(geometry));
+        assertEquals("{\"type\":\"MultiLineString\",\"coordinates\":[[[100.0,0.0],[101.0,1.0]],[[102.0,2.0],[103.0,3.0]]]}", JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiPointTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiPointTest.java
index 2239e66d1..745b01869 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiPointTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiPointTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.Geometry;
 import com.alibaba.fastjson.support.geo.MultiPoint;
 import org.junit.jupiter.api.Test;
@@ -18,12 +18,12 @@ public class MultiPointTest {
                 "    ]\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(MultiPoint.class, geometry.getClass());
 
-        assertEquals("{\"type\":\"MultiPoint\",\"coordinates\":[[100.0,0.0],[101.0,1.0]]}", JSON.toJSONString(geometry));
+        assertEquals("{\"type\":\"MultiPoint\",\"coordinates\":[[100.0,0.0],[101.0,1.0]]}", JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiPolygonTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiPolygonTest.java
index 3c71469c1..07e624067 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiPolygonTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/MultiPolygonTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.Geometry;
 import com.alibaba.fastjson.support.geo.MultiPolygon;
 import org.junit.jupiter.api.Test;
@@ -41,14 +41,14 @@ public class MultiPolygonTest {
                 "    ]\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(MultiPolygon.class, geometry.getClass());
 
         assertEquals(
                 "{\"type\":\"MultiPolygon\",\"coordinates\":[[[[102.0,2.0],[103.0,2.0],[103.0,3.0],[102.0,3.0],[102.0,2.0]]],[[[100.0,0.0],[101.0,0.0],[101.0,1.0],[100.0,1.0],[100.0,0.0]],[[100.2,0.2],[100.2,0.8],[100.8,0.8],[100.8,0.2],[100.2,0.2]]]]}"
-                , JSON.toJSONString(geometry));
+                , JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/PointTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/PointTest.java
index 55d8cbf4e..89ae5c703 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/PointTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/PointTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.Geometry;
 import com.alibaba.fastjson.support.geo.Point;
 import org.junit.jupiter.api.Test;
@@ -15,12 +15,12 @@ public class PointTest {
                 "    \"coordinates\": [100.0, 0.0]\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(Point.class, geometry.getClass());
 
-        assertEquals("{\"type\":\"Point\",\"coordinates\":[100.0,0.0]}", JSON.toJSONString(geometry));
+        assertEquals("{\"type\":\"Point\",\"coordinates\":[100.0,0.0]}", JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/PolygonTest.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/PolygonTest.java
index c17c8c951..e0fde632c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/PolygonTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/geo/PolygonTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.geo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.support.geo.Geometry;
 import com.alibaba.fastjson.support.geo.Polygon;
 import org.junit.jupiter.api.Test;
@@ -30,12 +30,12 @@ public class PolygonTest {
                 "    ]\n" +
                 "}";
 
-        Geometry geometry = JSON.parseObject(str, Geometry.class);
+        Geometry geometry = JsonMapper.parseJsonObject(str, Geometry.class);
         assertEquals(Polygon.class, geometry.getClass());
 
-        assertEquals("{\"type\":\"Polygon\",\"coordinates\":[[[100.0,0.0],[101.0,0.0],[101.0,1.0],[100.0,1.0],[100.0,0.0]],[[100.8,0.8],[100.8,0.2],[100.2,0.2],[100.2,0.8],[100.8,0.8]]]}", JSON.toJSONString(geometry));
+        assertEquals("{\"type\":\"Polygon\",\"coordinates\":[[[100.0,0.0],[101.0,0.0],[101.0,1.0],[100.0,1.0],[100.0,0.0]],[[100.8,0.8],[100.8,0.2],[100.2,0.2],[100.2,0.8],[100.8,0.8]]]}", JsonMapper.toJsonString(geometry));
 
-        String str2 = JSON.toJSONString(geometry);
-        assertEquals(str2, JSON.toJSONString(JSON.parseObject(str2, Geometry.class)));
+        String str2 = JsonMapper.toJsonString(geometry);
+        assertEquals(str2, JsonMapper.toJsonString(JsonMapper.parseJsonObject(str2, Geometry.class)));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1079.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1079.java
index ce6eeaeea..6531e0f2c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1079.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1079.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1000;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -23,7 +23,7 @@ public class Issue1079 {
                 "\t}]\n" +
                 "}";
 
-        JSON.parseObject(text, PdpResponse.class);
+        JsonMapper.parseJsonObject(text, PdpResponse.class);
 
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1080.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1080.java
index 30ed32904..5fbf24c7e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1080.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1080.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1000;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,15 +11,15 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1080 {
     @Test
     public void test_for_issue() throws Exception {
-        java.util.Date date = JSON.parseObject("\"2017-3-17 00:00:01\"", java.util.Date.class);
-        String json = JSON.toJSONString(date, "yyyy-MM-dd");
+        java.util.Date date = JsonMapper.parseJsonObject("\"2017-3-17 00:00:01\"", java.util.Date.class);
+        String json = JsonMapper.toJsonString(date, "yyyy-MM-dd");
         assertEquals("\"2017-03-17\"", json);
     }
 
     @Test
     public void test_for_issue_2() throws Exception {
-        java.util.Date date = JSON.parseObject("\"2017-3-7 00:00:01\"", java.util.Date.class);
-        String json = JSON.toJSONString(date, "yyyy-MM-dd");
+        java.util.Date date = JsonMapper.parseJsonObject("\"2017-3-7 00:00:01\"", java.util.Date.class);
+        String json = JsonMapper.toJsonString(date, "yyyy-MM-dd");
         assertEquals("\"2017-03-07\"", json);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1082.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1082.java
index 98d81242f..4a57a80b7 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1082.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1082.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1000;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONException;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertNotNull;
@@ -15,7 +14,7 @@ public class Issue1082 {
     public void test_for_issue() throws Exception {
         Throwable error = null;
         try {
-            Model_1082 m = (Model_1082) JSON.parseObject("{}", Model_1082.class);
+            Model_1082 m = (Model_1082) JsonMapper.parseJsonObject("{}", Model_1082.class);
         } catch (JSONException ex) {
             error = ex;
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1083.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1083.java
index 81a590ad2..d3d578daf 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1083.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1083.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1000;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -18,7 +17,7 @@ public class Issue1083 {
     public void test_for_issue() throws Exception {
         Map map = new HashMap();
         map.put("userId", 456);
-        String json = JSON.toJSONString(map, JSONWriter.Feature.WriteNonStringValueAsString);
+        String json = JsonMapper.toJsonString(map, JSONWriter.Feature.WriteNonStringValueAsString);
         assertEquals("{\"userId\":\"456\"}", json);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1085.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1085.java
index f317b5450..3baf42d39 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1085.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1085.java
@@ -1,11 +1,10 @@
 package com.alibaba.fastjson2.v1issues.issue_1000;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.reader.ObjectReader;
 import com.alibaba.fastjson2.reader.ObjectReaderCreator;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -16,7 +15,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1085 {
     @Test
     public void test_for_issue() throws Exception {
-        Model model = (Model) JSON.parseObject("{\"id\":123}", AbstractModel.class);
+        Model model = (Model) JsonMapper.parseJsonObject("{\"id\":123}", AbstractModel.class);
         assertEquals(123, model.id);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1086.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1086.java
index 7e6630bc9..ce9827671 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1086.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1086.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1000;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertTrue;
@@ -12,7 +11,7 @@ import static org.junit.jupiter.api.Assertions.assertTrue;
 public class Issue1086 {
     @Test
     public void test_for_issue() throws Exception {
-        Model model = JSON.parseObject("{\"flag\":1}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"flag\":1}", Model.class);
         assertTrue(model.flag);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1089.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1089.java
index 217488890..5c7150141 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1089.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1089.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1000;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -13,7 +12,7 @@ public class Issue1089 {
     @Test
     public void test_for_issue() throws Exception {
         String json = "{\"ab\":123,\"a_b\":456}";
-        TestBean tb = JSON.parseObject(json, TestBean.class);
+        TestBean tb = JsonMapper.parseJsonObject(json, TestBean.class);
         assertEquals(123, tb.getAb());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1089_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1089_private.java
index 34fc6ce5f..23210c52c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1089_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1000/Issue1089_private.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1000;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -13,7 +12,7 @@ public class Issue1089_private {
     @Test
     public void test_for_issue() throws Exception {
         String json = "{\"ab\":123,\"a_b\":456}";
-        TestBean tb = JSON.parseObject(json, TestBean.class);
+        TestBean tb = JsonMapper.parseJsonObject(json, TestBean.class);
         assertEquals(123, tb.getAb());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1109.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1109.java
index e873b0889..87d6ac77b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1109.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1109.java
@@ -1,7 +1,5 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
 import org.apache.commons.lang3.tuple.Pair;
 import org.junit.jupiter.api.Test;
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1121.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1121.java
index ae43e422c..4266712b5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1121.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1121.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -24,7 +23,7 @@ public class Issue1121 {
         result.put("user",userObject);
         result.put("admin",userObject);
 
-        String json = JSON.toJSONString(result, JSONWriter.Feature.PrettyFormat);
+        String json = JsonMapper.toJsonString(result, JSONWriter.Feature.PrettyFormat);
         assertEquals("{\n" +
                 "\t\"host\":\"127.0.0.1\",\n" +
                 "\t\"port\":3306,\n" +
@@ -38,7 +37,7 @@ public class Issue1121 {
                 "\t}\n" +
                 "}", json);
 
-        JSONObject jsonObject2 = JSON.parseObject(json);
+        JSONObject jsonObject2 = JsonMapper.parseJsonObject(json);
         assertEquals(result, jsonObject2);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1134.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1134.java
index 5a58a94f5..4338fe9b3 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1134.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1134.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -21,7 +20,7 @@ public class Issue1134 {
         model.blockpos.z = 554;
         model.passCode = "010";
 
-        String text = JSON.toJSONString(model);
+        String text = JsonMapper.toJsonString(model);
         assertEquals("{\"Dimension\":0,\"PassCode\":\"010\",\"BlockPos\":{\"x\":526,\"y\":65,\"z\":554}}", text);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1138.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1138.java
index f61d11442..5b96e367c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1138.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1138.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -18,11 +17,11 @@ public class Issue1138 {
         model.name = "gaotie";
 
         // {"id":1001,"name":"gaotie"}
-        String text_normal = JSON.toJSONString(model);
+        String text_normal = JsonMapper.toJsonString(model);
         assertEquals("{\"id\":1001,\"name\":\"gaotie\"}", text_normal);
 
         // [1001,"gaotie"]
-        String text_beanToArray = JSON.toJSONString(model, JSONWriter.Feature.BeanToArray);
+        String text_beanToArray = JsonMapper.toJsonString(model, JSONWriter.Feature.BeanToArray);
         assertEquals("[1001,\"gaotie\"]", text_beanToArray);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1140.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1140.java
index 4c054463a..9cb00f79e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1140.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1140.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.io.ByteArrayOutputStream;
@@ -17,7 +16,7 @@ public class Issue1140 {
         String s = "\uD83C\uDDEB\uD83C\uDDF7";
 
         ByteArrayOutputStream out = new ByteArrayOutputStream();
-        JSON.writeTo(out, s);
+        JsonMapper.writeToOutputStream(out, s);
 
         String str = new String(out.toByteArray());
         assertEquals("\"\uD83C\uDDEB\uD83C\uDDF7\"", str);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1144.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1144.java
index 007625fe2..0b0678720 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1144.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1144.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -13,7 +12,7 @@ public class Issue1144 {
     @Test
     public void test_issue_1144() throws Exception {
         Model model = new Model();
-        String json = JSON.toJSONString(model);
+        String json = JsonMapper.toJsonString(model);
         assertEquals("{\"f0\":0,\"f1\":0,\"f2\":0}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146.java
index af4f13e1e..de885dd46 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
 import com.alibaba.fastjson2.annotation.JSONType;
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -13,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1146 {
     @Test
     public void test_for_issue() throws Exception {
-        String json = JSON.toJSONString(new Bean());
+        String json = JsonMapper.toJsonString(new Bean());
         assertEquals("{\"id\":101}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146C.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146C.java
index 6ac0b2988..05add43e5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146C.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146C.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONType;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -13,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1146C {
     @Test
     public void test_for_issue() throws Exception {
-        String json = JSON.toJSONString(new Bean());
+        String json = JsonMapper.toJsonString(new Bean());
         assertEquals("{\"id\":101}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1150.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1150.java
index 7289bb465..40092400f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1150.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1150.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.List;
@@ -14,13 +13,13 @@ import static org.junit.jupiter.api.Assertions.assertNull;
 public class Issue1150 {
     @Test
     public void test_for_issue() throws Exception {
-        Model model = JSON.parseObject("{\"values\":\"\"}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"values\":\"\"}", Model.class);
         assertNull(model.values);
     }
 
     @Test
     public void test_for_issue_array() throws Exception {
-        Model2 model = JSON.parseObject("{\"values\":\"\"}", Model2.class);
+        Model2 model = JsonMapper.parseJsonObject("{\"values\":\"\"}", Model2.class);
         assertNull(model.values);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1151.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1151.java
index 8a78b8bf2..2b960e4cc 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1151.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1151.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.ArrayList;
@@ -22,10 +21,10 @@ public class Issue1151 {
         a.list.add(new C(1001));
         a.list.add(new C(1002));
 
-        String json = JSON.toJSONString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json = JsonMapper.toJsonString(a, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"list\":[{\"@type\":\"com.alibaba.fastjson2.v1issues.issue_1100.Issue1151$C\",\"id\":1001},{\"@type\":\"com.alibaba.fastjson2.v1issues.issue_1100.Issue1151$C\",\"id\":1002}]}", json);
 
-        A a2 = JSON.parseObject(json, A.class, JSONReader.Feature.SupportAutoType);
+        A a2 = JsonMapper.parseJsonObject(json, A.class, JSONReader.Feature.SupportAutoType);
         assertSame(a2.list.get(0).getClass(), C.class);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1165.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1165.java
index e93787885..2a5261da7 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1165.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1165.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -15,7 +14,7 @@ public class Issue1165 {
         Model model = new Model();
         model.__v = 3;
 
-        String json = JSON.toJSONString(model);
+        String json = JsonMapper.toJsonString(model);
         assertEquals("{\"__v\":3}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177.java
index e315b56b1..4965bbc87 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertNotNull;
@@ -15,7 +14,7 @@ public class Issue1177 {
     @Test
     public void test_for_issue() throws Exception {
         String text = "{\"a\":{\"b\":\"c\",\"g\":{\"e\":\"f\"}},\"d\":{\"a\":\"f\",\"h\":[\"s1\"]}} ";
-        JSONObject jsonObject = JSON.parseObject(text);
+        JSONObject jsonObject = JsonMapper.parseJsonObject(text);
         Object eval = JSONPath.eval(jsonObject, "$..a");
         assertNotNull(eval);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_1.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_1.java
index db2b75579..250f3e0b8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_1.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_1.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -15,7 +14,7 @@ public class Issue1177_1 {
     @Test
     public void test_for_issue() throws Exception {
         String text = "{\"a\":{\"x\":\"y\"},\"b\":{\"x\":\"y\"}}";
-        JSONObject jsonObject = JSON.parseObject(text);
+        JSONObject jsonObject = JsonMapper.parseJsonObject(text);
         System.out.println(jsonObject);
         String jsonpath = "$..x";
         String value="y2";
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_2.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_2.java
index b2ad1acda..e38bc4c35 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_2.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_2.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONPath;
 import com.alibaba.fastjson2.TypeReference;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.Map;
@@ -17,12 +16,12 @@ public class Issue1177_2 {
     @Test
     public void test_for_issue() throws Exception {
         String text = "{\"a\":{\"x\":\"y\"},\"b\":{\"x\":\"y\"}}";
-        Map<String, Model> jsonObject = JSON.parseObject(text, new TypeReference<Map<String, Model>>(){}.getType());
-        System.out.println(JSON.toJSONString(jsonObject));
+        Map<String, Model> jsonObject = JsonMapper.parseJsonObject(text, new TypeReference<Map<String, Model>>(){}.getType());
+        System.out.println(JsonMapper.toJsonString(jsonObject));
         String jsonpath = "$..x";
         String value="y2";
         JSONPath.set(jsonObject, jsonpath, value);
-        assertEquals("{\"a\":{\"x\":\"y2\"},\"b\":{\"x\":\"y2\"}}", JSON.toJSONString(jsonObject));
+        assertEquals("{\"a\":{\"x\":\"y2\"},\"b\":{\"x\":\"y2\"}}", JsonMapper.toJsonString(jsonObject));
     }
 
     public static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_3.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_3.java
index 2a81b4f06..421d80c42 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_3.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_3.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONPath;
 import com.alibaba.fastjson2.TypeReference;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.List;
@@ -17,12 +16,12 @@ public class Issue1177_3 {
     @Test
     public void test_for_issue() throws Exception {
         String text = "[{\"x\":\"y\"},{\"x\":\"y\"}]";
-        List<Model> jsonObject = JSON.parseObject(text, new TypeReference<List<Model>>(){}.getType());
-        System.out.println(JSON.toJSONString(jsonObject));
+        List<Model> jsonObject = JsonMapper.parseJsonObject(text, new TypeReference<List<Model>>(){}.getType());
+        System.out.println(JsonMapper.toJsonString(jsonObject));
         String jsonpath = "$..x";
         String value="y2";
         JSONPath.set(jsonObject, jsonpath, value);
-        assertEquals("[{\"x\":\"y2\"},{\"x\":\"y2\"}]", JSON.toJSONString(jsonObject));
+        assertEquals("[{\"x\":\"y2\"},{\"x\":\"y2\"}]", JsonMapper.toJsonString(jsonObject));
 
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_4.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_4.java
index 35a295e77..cc9ea9f86 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_4.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1177_4.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.List;
@@ -16,12 +15,12 @@ public class Issue1177_4 {
     @Test
     public void test_for_issue() throws Exception {
         String text = "{\"models\":[{\"x\":\"y\"},{\"x\":\"y\"}]}";
-        Root root = JSON.parseObject(text, Root.class);
-        System.out.println(JSON.toJSONString(root));
+        Root root = JsonMapper.parseJsonObject(text, Root.class);
+        System.out.println(JsonMapper.toJsonString(root));
         String jsonpath = "$..x";
         String value="y2";
         JSONPath.set(root, jsonpath, value);
-        assertEquals("{\"models\":[{\"x\":\"y2\"},{\"x\":\"y2\"}]}", JSON.toJSONString(root));
+        assertEquals("{\"models\":[{\"x\":\"y2\"},{\"x\":\"y2\"}]}", JsonMapper.toJsonString(root));
     }
 
     public static class Root {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1178.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1178.java
index 53c56046f..7250e0014 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1178.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1178.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.io.Serializable;
@@ -19,7 +18,7 @@ public class Issue1178 {
                 "    }\n" +
                 "}";
 
-        JSONObject jsonObject = JSON.parseObject(json);
+        JSONObject jsonObject = JsonMapper.parseJsonObject(json);
         TestModel loginResponse = jsonObject.toJavaObject(TestModel.class); // TODO toJavaObject
 
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1188.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1188.java
index 2eb7f6e60..8e8fd789d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1188.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1188.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -15,7 +15,7 @@ public class Issue1188 {
     @Test
     public void test_for_issue_1188() throws Exception {
         String json = "{\"ids\":\"a1,a2\",\"name\":\"abc\"}";
-        Info info = JSON.parseObject(json, Info.class);
+        Info info = JsonMapper.parseJsonObject(json, Info.class);
         assertNull(info.ids);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1189.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1189.java
index f7f9082f8..11aa7a1f7 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1189.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1189.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Map;
@@ -14,7 +13,7 @@ public class Issue1189 {
     public void test_for_issue() throws Exception {
         String str = new String("{\"headernotificationType\": \"PUSH\",\"headertemplateNo\": \"99\",\"headerdestination\": [{\"target\": \"all\",\"targetvalue\": \"all\"}],\"body\": [{\"title\": \"预约超时\",\"body\": \"您的预约已经超时\"}]}");
 
-        JsonBean objeclt = JSON.parseObject(str, JsonBean.class);
+        JsonBean objeclt = JsonMapper.parseJsonObject(str, JsonBean.class);
         Map<String, String> list = objeclt.getBody();
         System.out.println(list.get("body"));
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1120.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1120.java
index 0736f3e3a..0c3c38e82 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1120.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1120.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -15,7 +15,7 @@ public class Issue1120 {
         Model model = new Model();
         model.setReqNo("123");
 
-        assertEquals("{\"REQ_NO\":\"123\"}", JSON.toJSONString(model));
+        assertEquals("{\"REQ_NO\":\"123\"}", JsonMapper.toJsonString(model));
     }
 
     public static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1120C.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1120C.java
index 85994a2d3..02ab5d956 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1120C.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1120C.java
@@ -1,7 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
-import com.alibaba.fastjson2.JSON;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -15,7 +15,7 @@ public class Issue1120C {
         Model model = new Model();
         model.setReqNo("123");
 
-        assertEquals("{\"REQ_NO\":\"123\"}", JSON.toJSONString(model));
+        assertEquals("{\"REQ_NO\":\"123\"}", JsonMapper.toJsonString(model));
     }
 
     public static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1202.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1202.java
index fc1710ddc..be475b234 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1202.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1202.java
@@ -1,13 +1,12 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.annotation.JSONField;
 import com.alibaba.fastjson2.reader.ObjectReader;
 import com.alibaba.fastjson2.reader.ObjectReaderCreator;
 import com.alibaba.fastjson2.reader.ObjectReaderCreatorASM;
 import com.alibaba.fastjson2.reader.ObjectReaderCreatorLambda;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.Date;
@@ -21,7 +20,7 @@ public class Issue1202 {
     @Test
     public void test_for_issue_0() throws Exception {
         String text = "{\"date\":\"Apr 27, 2017 5:02:17 PM\"}";
-        Model1 model = JSON.parseObject(text, Model1.class);
+        Model1 model = JsonMapper.parseJsonObject(text, Model1.class);
         assertNotNull(model.date);
     }
 
@@ -46,7 +45,7 @@ public class Issue1202 {
     @Test
     public void test_for_issue_2() throws Exception {
         String text = "{\"date\":\"Apr 27, 2017 5:02:17 PM\"}";
-        Model2 model = JSON.parseObject(text, Model2.class);
+        Model2 model = JsonMapper.parseJsonObject(text, Model2.class);
         assertNotNull(model.date);
     }
 
@@ -71,7 +70,7 @@ public class Issue1202 {
     @Test
     public void test_for_issue_3() throws Exception {
         String text = "{\"date\":\"Apr 27, 2017 5:02:17 PM\"}";
-        Model3 model = JSON.parseObject(text, Model3.class);
+        Model3 model = JsonMapper.parseJsonObject(text, Model3.class);
         assertNotNull(model.date);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1203.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1203.java
index fab171d88..7a4e4a40e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1203.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1203.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -19,7 +18,7 @@ public class Issue1203 {
         strArr[3] = "d";
         strArr[4] = "";
 
-        String json = JSON.toJSONString(strArr, JSONWriter.Feature.NullAsDefaultValue);
+        String json = JsonMapper.toJsonString(strArr, JSONWriter.Feature.NullAsDefaultValue);
         assertEquals("[\"a\",\"b\",\"\",\"d\",\"\"]", json);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1222.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1222.java
index 1238b711e..04cf3a320 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1222.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1222.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -14,7 +14,7 @@ public class Issue1222 {
     public void test_for_issue() throws Exception {
         Model model = new Model();
         model.type = Type.A;
-        String text = JSON.toJSONString(model, JSONWriter.Feature.WriteEnumUsingToString);
+        String text = JsonMapper.toJsonString(model, JSONWriter.Feature.WriteEnumUsingToString);
         assertEquals("{\"type\":\"TypeA\"}", text);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1222_1.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1222_1.java
index 6ad978c84..7aee0bba6 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1222_1.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1222_1.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -15,7 +14,7 @@ public class Issue1222_1 {
     public void test_for_issue() throws Exception {
         Model model = new Model();
         model.type = Type.A;
-        String text = JSON.toJSONString(model, JSONWriter.Feature.WriteEnumUsingToString);
+        String text = JsonMapper.toJsonString(model, JSONWriter.Feature.WriteEnumUsingToString);
         assertEquals("{\"type\":\"TypeA\"}", text);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1225.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1225.java
index 0eebe07fc..30e350b4d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1225.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1225.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.TypeReference;
 import org.junit.jupiter.api.Test;
 
@@ -16,7 +16,7 @@ public class Issue1225 {
 
     @Test
     public void test_parseObject_0() {
-        BaseGenericType<List<String>> o = JSON.parseObject("{\"data\":[\"1\",\"2\",\"3\"]}",
+        BaseGenericType<List<String>> o = JsonMapper.parseJsonObject("{\"data\":[\"1\",\"2\",\"3\"]}",
                 new TypeReference<BaseGenericType<List<String>>>() {
                 }.getType());
         assertEquals("2", o.data.get(1));
@@ -25,14 +25,14 @@ public class Issue1225 {
     @Test
     public void test_parseObject_1() {
         Type type = new TypeReference<ExtendGenericType<String>>() {}.getType();
-        ExtendGenericType<String> o = JSON.parseObject("{\"data\":[\"1\",\"2\",\"3\"]}", type);
+        ExtendGenericType<String> o = JsonMapper.parseJsonObject("{\"data\":[\"1\",\"2\",\"3\"]}", type);
         assertEquals("2", o.data.get(1));
     }
 
 
     @Test
     public void test_parseObject_2() {
-        SimpleGenericObject object = JSON.parseObject("{\"data\":[\"1\",\"2\",\"3\"],\"a\":\"a\"}",
+        SimpleGenericObject object = JsonMapper.parseJsonObject("{\"data\":[\"1\",\"2\",\"3\"],\"a\":\"a\"}",
                 SimpleGenericObject.class);
 
         assertEquals("2", object.data.get(1));
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1226.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1226.java
index 9656a7678..b7c7ca2b1 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1226.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1226.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -10,14 +10,14 @@ public class Issue1226 {
     @Test
     public void test_for_issue() throws Exception {
         String json = "{\"c\":\"c\"}";
-        TestBean tb1 = JSON.parseObject(json, TestBean.class);
+        TestBean tb1 = JsonMapper.parseJsonObject(json, TestBean.class);
         assertEquals('c', tb1.getC());
 
-        TestBean2 tb2 = JSON.parseObject(json, TestBean2.class);
+        TestBean2 tb2 = JsonMapper.parseJsonObject(json, TestBean2.class);
         assertEquals('c', tb2.getC().charValue());
 
-        String json2 = JSON.toJSONString(tb2);
-        JSONObject jo = JSON.parseObject(json2);
+        String json2 = JsonMapper.toJsonString(tb2);
+        JSONObject jo = JsonMapper.parseJsonObject(json2);
 
         TestBean tb12 = jo.toJavaObject(TestBean.class);
         assertEquals('c', tb12.getC());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1227.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1227.java
index 42bfad3fb..9783ba36f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1227.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1227.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.*;
@@ -13,11 +12,11 @@ public class Issue1227 {
         String t2 = "{\"state\":2,\"msg\":\"\ufeffmsg2222\",\"data\":[]}";
 
         try {
-            Bean model = JSON.parseObject(t2, Bean.class);
+            Bean model = JsonMapper.parseJsonObject(t2, Bean.class);
             assertEquals("\uFEFFmsg2222",model.msg);
 
             model.msg = "\uFEFFss";
-            String t3 = JSON.toJSONString(model);
+            String t3 = JsonMapper.toJsonString(model);
             assertTrue(t3.contains(model.msg));
         } catch ( Exception e) {
             e.printStackTrace();
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1229.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1229.java
index a8bb8424b..620e03e74 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1229.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1229.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.TypeReference;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.lang.reflect.Type;
@@ -17,23 +16,23 @@ import static org.junit.jupiter.api.Assertions.*;
 public class Issue1229 {
     @Test
     public void test_for_issue() throws Exception {
-        final Object parsed = JSON.parse("{\"data\":{}}");
+        final Object parsed = JsonMapper.parseJson("{\"data\":{}}");
         assertTrue(parsed instanceof JSONObject);
         assertEquals(JSONObject.class, ((JSONObject)parsed).get("data").getClass());
 
         Type type = new TypeReference<Result<Data>>() {}.getType();
-        final Result<Data> result = JSON.parseObject("{\"data\":{}}", type);
+        final Result<Data> result = JsonMapper.parseJsonObject("{\"data\":{}}", type);
         assertNotNull(result.data);
         assertTrue(result.data instanceof Data);
 
-        final Result<List<Data>> result2 = JSON.parseObject("{\"data\":[]}", new TypeReference<Result<List<Data>>>(){}.getType());
+        final Result<List<Data>> result2 = JsonMapper.parseJsonObject("{\"data\":[]}", new TypeReference<Result<List<Data>>>(){}.getType());
         assertNotNull(result2.data);
         assertTrue(result2.data instanceof List);
         assertEquals(0, result2.data.size());
     }
 
     public void parseErr() throws Exception {
-        JSON.parseObject("{\"data\":{}}", new TypeReference<Result<List<Data>>>(){}.getType());
+        JsonMapper.parseJsonObject("{\"data\":{}}", new TypeReference<Result<List<Data>>>(){}.getType());
         fail("should be failed due to error json");
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1233.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1233.java
index 2e3c3c51c..bde0a9fdb 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1233.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1233.java
@@ -1,7 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
 import com.alibaba.fastjson2.annotation.JSONType;
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -16,10 +16,10 @@ import static org.junit.jupiter.api.Assertions.assertNotNull;
 public class Issue1233 {
     @Test
     public void test_for_issue() throws Exception {
-        JSONObject jsonObject = JSON.parseObject("{\"type\":\"floorV2\",\"templateId\":\"x123\"}");
+        JSONObject jsonObject = JsonMapper.parseJsonObject("{\"type\":\"floorV2\",\"templateId\":\"x123\"}");
 
-        JSON.mixIn(Area.class, AreaMixIn.class);
-        JSON.mixIn(FloorV2.class, FloorV2MixIn.class);
+        JsonMapper.addMixIn(Area.class, AreaMixIn.class);
+        JsonMapper.addMixIn(FloorV2.class, FloorV2MixIn.class);
 
         FloorV2 floorV2 = (FloorV2) jsonObject.toJavaObject(Area.class);
         assertNotNull(floorV2);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1235.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1235.java
index f5d48820e..3be787b01 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1235.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1235.java
@@ -1,10 +1,9 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONType;
-import com.alibaba.fastjson2.JSON;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -18,13 +17,13 @@ public class Issue1235 {
     public void test_for_issue() throws Exception {
         String json = "{\"type\":\"floorV2\",\"templateId\":\"x123\"}";
 
-        FloorV2 floorV2 = (FloorV2) JSON.parseObject(json, Area.class);
+        FloorV2 floorV2 = (FloorV2) JsonMapper.parseJsonObject(json, Area.class);
         assertNotNull(floorV2);
         assertNotNull(floorV2.templateId);
         assertEquals("x123", floorV2.templateId);
         assertEquals("floorV2", floorV2.type);
 
-        String json2 = JSON.toJSONString(floorV2, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json2 = JsonMapper.toJsonString(floorV2, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"type\":\"floorV2\",\"templateId\":\"x123\"}", json2);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1235_noasm.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1235_noasm.java
index 99d869233..529e99e14 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1235_noasm.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1235_noasm.java
@@ -1,10 +1,9 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONType;
-import com.alibaba.fastjson2.JSON;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -18,13 +17,13 @@ public class Issue1235_noasm {
     public void test_for_issue() throws Exception {
         String json = "{\"type\":\"floorV2\",\"templateId\":\"x123\"}";
 
-        FloorV2 floorV2 = (FloorV2) JSON.parseObject(json, Area.class);
+        FloorV2 floorV2 = (FloorV2) JsonMapper.parseJsonObject(json, Area.class);
         assertNotNull(floorV2);
         assertNotNull(floorV2.templateId);
         assertEquals("x123", floorV2.templateId);
         assertEquals("floorV2", floorV2.type);
 
-        String json2 = JSON.toJSONString(floorV2, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
+        String json2 = JsonMapper.toJsonString(floorV2, JSONWriter.Feature.NotWriteRootClassName, JSONWriter.Feature.WriteClassName);
         assertEquals("{\"type\":\"floorV2\",\"templateId\":\"x123\"}", json2);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1240.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1240.java
index 3e95b72e6..a5733aaed 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1240.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1240.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 import org.springframework.util.LinkedMultiValueMap;
 
@@ -15,7 +14,7 @@ public class Issue1240 {
 //        parserConfig.setAutoTypeSupport(true);
         LinkedMultiValueMap<String, String> result = new LinkedMultiValueMap();
         result.add("test", "11111");
-        String test = JSON.toJSONString(result, JSONWriter.Feature.WriteClassName);
+        String test = JsonMapper.toJsonString(result, JSONWriter.Feature.WriteClassName);
 //        JSON.parseObject(test, Object.class, parserConfig, JSON.DEFAULT_PARSER_FEATURE);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1246.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1246.java
index 86e24074f..318717937 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1246.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1246.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -15,21 +15,21 @@ public class Issue1246 {
         B b = new B();
         b.setX("xx");
 
-        String test = JSON.toJSONString( b );
+        String test = JsonMapper.toJsonString( b );
         System.out.println(test);
         assertEquals("{}", test);
 
         C c = new C();
         c.ab = b ;
 
-        String testC = JSON.toJSONString( c );
+        String testC = JsonMapper.toJsonString( c );
         System.out.println(testC);
         assertEquals("{\"ab\":{}}",testC);
 
         D d = new D();
         d.setAb( b );
 
-        String testD = JSON.toJSONString( d );
+        String testD = JsonMapper.toJsonString( d );
         System.out.println(testD);
         assertEquals("{\"ab\":{}}",testD);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1254.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1254.java
index 9cfb5558f..dafdfa43f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1254.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1254.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -15,7 +14,7 @@ public class Issue1254 {
     public void test_for_issue() throws Exception {
         A a = new A();
         a._parentId = "001";
-        String test = JSON.toJSONString(a);
+        String test = JsonMapper.toJsonString(a);
         System.out.println(test);
         assertEquals("{\"_parentId\":\"001\"}", test);
 
@@ -23,7 +22,7 @@ public class Issue1254 {
         b.set_parentId("001");
 
 
-        String testB = JSON.toJSONString(b);
+        String testB = JsonMapper.toJsonString(b);
         System.out.println(testB);
         assertEquals("{\"_parentId\":\"001\"}", testB);
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1256.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1256.java
index d5664b87b..37dc41002 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1256.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1256.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -29,7 +28,7 @@ public class Issue1256 {
         map.put("key_random",-1193959466L);
         map.put("key_int",10000);
 
-        String jsonString = JSON.toJSONString(map);
+        String jsonString = JsonMapper.toJsonString(map);
         assertTrue(jsonString.contains("Mike"));
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1262.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1262.java
index 9fc9c16f2..f880679eb 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1262.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1262.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Map;
@@ -13,7 +12,7 @@ import java.util.concurrent.ConcurrentHashMap;
 public class Issue1262 {
     @Test
     public void test_for_issue() throws Exception {
-        Model model = JSON.parseObject("{\"chatterMap\":{}}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"chatterMap\":{}}", Model.class);
     }
 
     public static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1265.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1265.java
index 6e9309fb4..3408c97f6 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1265.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1265.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.TypeReference;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.lang.reflect.Type;
@@ -17,13 +16,13 @@ public class Issue1265 {
     @Test
     public void test_0() {
         Type type = new TypeReference<Response>(){}.getType();
-        Object t = ((Response) JSON.parseObject("{\"value\":{\"id\":123}}", type)).value;
+        Object t = ((Response) JsonMapper.parseJsonObject("{\"value\":{\"id\":123}}", type)).value;
         assertEquals(123, ((JSONObject) t).getIntValue("id"));
 
-        T1 t1 = ((Response<T1>) JSON.parseObject("{\"value\":{\"id\":123}}", new TypeReference<Response<T1>>(){}.getType())).value;
+        T1 t1 = ((Response<T1>) JsonMapper.parseJsonObject("{\"value\":{\"id\":123}}", new TypeReference<Response<T1>>(){}.getType())).value;
         assertEquals(123, t1.id);
 
-        T2 t2 = ((Response<T2>) JSON.parseObject("{\"value\":{\"id\":123}}", new TypeReference<Response<T2>>(){}.getType())).value;
+        T2 t2 = ((Response<T2>) JsonMapper.parseJsonObject("{\"value\":{\"id\":123}}", new TypeReference<Response<T2>>(){}.getType())).value;
         assertEquals(123, t2.id);
 
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1272.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1272.java
index 56f4b4296..7899f51b1 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1272.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1272.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONException;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -17,7 +16,7 @@ public class Issue1272 {
         Exception exception = null;
 
         try {
-            JSON.toJSONString(new Point());
+            JsonMapper.toJsonString(new Point());
         }catch (JSONException ex) {
             exception = ex;
         }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1272_IgnoreError.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1272_IgnoreError.java
index 5e0529a5c..f1bd0cb73 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1272_IgnoreError.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1272_IgnoreError.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -12,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1272_IgnoreError {
     @Test
     public void test_for_issue() throws Exception {
-        String text = JSON.toJSONString(new Point(), JSONWriter.Feature.IgnoreErrorGetter);
+        String text = JsonMapper.toJsonString(new Point(), JSONWriter.Feature.IgnoreErrorGetter);
         assertEquals("{}", text);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1274.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1274.java
index ae4b11d5e..828475b6e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1274.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1274.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.filter.NameFilter;
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -29,7 +28,7 @@ public class Issue1274 {
         };
 
         // test for  JSON.toJSONString(user,filter);
-        String jsonString = JSON.toJSONString(user,filter);
+        String jsonString = JsonMapper.toJsonString(user,filter);
         System.out.println(jsonString);
         assertEquals("{\"id\":1,\"nt\":\"name\"}", jsonString);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1276.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1276.java
index cddefdad9..f001f279e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1276.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1276.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -13,13 +12,13 @@ public class Issue1276 {
     @Test
     public void test_for_issue() throws Exception {
         MyException myException = new MyException(100,"error msg");
-        String str = JSON.toJSONString(myException);
+        String str = JsonMapper.toJsonString(myException);
         System.out.println(str);
 
-        MyException myException1 = JSON.parseObject(str, MyException.class);
+        MyException myException1 = JsonMapper.parseJsonObject(str, MyException.class);
         assertEquals(myException.getCode(), myException1.getCode());
 
-        String str1 = JSON.toJSONString(myException1);
+        String str1 = JsonMapper.toJsonString(myException1);
         assertEquals(str, str1);
 
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1278.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1278.java
index de572a6ff..384b2e2bd 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1278.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1278.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -17,12 +16,12 @@ public class Issue1278 {
 
         String json1 = "{\"name\":\"name\",\"id\":1}";
         String json2 = "{\"user\":\"user\",\"id\":2}";
-        AlternateNames c1 = JSON.parseObject(json1, AlternateNames.class);
+        AlternateNames c1 = JsonMapper.parseJsonObject(json1, AlternateNames.class);
 
         assertEquals("name",c1.name);
         assertEquals(1,c1.id);
 
-        AlternateNames c2 = JSON.parseObject(json2, AlternateNames.class);
+        AlternateNames c2 = JsonMapper.parseJsonObject(json2, AlternateNames.class);
 
         assertEquals("user",c2.name);
         assertEquals(2,c2.id);
@@ -41,13 +40,13 @@ public class Issue1278 {
         assertEquals("user",c2.name);
         assertEquals(2,c2.id);
 
-        JSONObject jsonObject = JSON.parseObject(json1);
+        JSONObject jsonObject = JsonMapper.parseJsonObject(json1);
         c1 = jsonObject.toJavaObject(AlternateNames.class);
 
         assertEquals("name",c1.name);
         assertEquals(1,c1.id);
 
-        jsonObject = JSON.parseObject(json2);
+        jsonObject = JsonMapper.parseJsonObject(json2);
         c2 = jsonObject.toJavaObject(AlternateNames.class);
 
         assertEquals("user",c2.name);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1293.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1293.java
index c7868a3d7..1173dab97 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1293.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1293.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertNull;
@@ -15,13 +15,13 @@ public class Issue1293 {
     public void test_for_issue() {
         String data = "{\"idType\":\"123123\",\"userType\":\"134\",\"count\":\"123123\"}";
         {
-            Bean test = JSON.parseObject(data, Bean.class);
+            Bean test = JsonMapper.parseJsonObject(data, Bean.class);
 
             assertNull(test.idType);
             assertNull(test.userType);
         }
 
-        Bean test = JSON.parseObject(data, Bean.class);
+        Bean test = JsonMapper.parseJsonObject(data, Bean.class);
         assertNull(test.idType);
         assertNull(test.userType);
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1298.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1298.java
index 22dadf0d0..a4653d88a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1298.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1200/Issue1298.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.Date;
@@ -21,7 +20,7 @@ public class Issue1298 {
 
         Date date = object.getObject("date", Date.class);
 
-        assertEquals("\"2017-06-29T10:36:30+08:00\"", JSON.toJSONString(date, "iso8601"));
+        assertEquals("\"2017-06-29T10:36:30+08:00\"", JsonMapper.toJsonString(date, "iso8601"));
     }
 
     @Test
@@ -32,8 +31,8 @@ public class Issue1298 {
 
         Date date = object.getObject("date", Date.class);
 
-        assertEquals("\"2017-08-15T20:00:00+08:00\"", JSON.toJSONString(date, "iso8601"));
+        assertEquals("\"2017-08-15T20:00:00+08:00\"", JsonMapper.toJsonString(date, "iso8601"));
 
-        JSON.parseObject("\"2017-08-15 20:00:00.000\"", Date.class);
+        JsonMapper.parseJsonObject("\"2017-08-15 20:00:00.000\"", Date.class);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1303.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1303.java
index c6afcba7f..357542392 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1303.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1303.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONArray;
 import com.alibaba.fastjson2.JSONObject;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -15,7 +14,7 @@ public class Issue1303 {
     @Test
     public void test_for_issue() {
         String jsonString = "[{\"author\":{\"__type\":\"Pointer\",\"className\":\"_User\",\"objectId\":\"a876c49c18\"},\"createdAt\":\"2017-07-02 20:06:13\",\"imgurl\":\"https://ss0.bdstatic.com/70cFuHSh_Q1YnxGkpoWK1HF6hhy/it/u=11075891,34401011&fm=117&gp=0.jpg\",\"name\":\"衣架\",\"objectId\":\"029d5493cd\",\"prices\":\"1\",\"updatedAt\":\"2017-07-02 20:06:13\"}]";
-        JSONArray jsonArray = JSON.parseArray(jsonString);
+        JSONArray jsonArray = JsonMapper.parseJsonArray(jsonString);
         //jsonArray = new JSONArray(jsonArray);//这一句打开也一样是正确的
         double total = 0;
         for (int i = 0; i <jsonArray.size() ; i++) {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1306.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1306.java
index a1d4c4433..886bb706a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1306.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1306.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.io.Serializable;
@@ -21,9 +20,9 @@ public class Issue1306 {
         Goods goods = new Goods();
         goods.setProperties(Arrays.asList(new Goods.Property()));
         TT tt = new TT(goods);
-        String json = JSON.toJSONString(tt);
+        String json = JsonMapper.toJsonString(tt);
         assertEquals("{\"goodsList\":[{\"properties\":[{}]}]}", json);
-        TT n = JSON.parseObject(json, TT.class);
+        TT n = JsonMapper.parseJsonObject(json, TT.class);
         assertNotNull(n);
         assertNotNull(n.getGoodsList());
         assertNotNull(n.getGoodsList().get(0));
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1307.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1307.java
index 50cfff080..ffc00656e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1307.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1307.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.filter.ValueFilter;
 import com.alibaba.fastjson2.filter.Filter;
 import org.junit.Assert;
@@ -36,7 +36,7 @@ public class Issue1307 {
         params.add(data);
         //fail Actual   :[{"name":"ace"}]
         assertEquals("[{\"name\":\"mark-ace\"}]"
-                , JSON.toJSONString(params,
+                , JsonMapper.toJsonString(params,
                         new Filter[]{
                                 contextValueFilter
                         })
@@ -52,7 +52,7 @@ public class Issue1307 {
         params.add(data);
         //success
         Assert.assertEquals("[{\"name\":\"ace\"}]"
-                , JSON.toJSONString(params,
+                , JsonMapper.toJsonString(params,
                         new Filter[]{
                                 valueFilter
                         })
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1310.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1310.java
index 002931308..b56327010 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1310.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1310.java
@@ -1,11 +1,10 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.annotation.JSONField;
 import com.alibaba.fastjson2.reader.ObjectReader;
 import com.alibaba.fastjson2.reader.ObjectReaderCreatorLambda;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -19,9 +18,9 @@ public class Issue1310 {
         Model model = new Model();
         model.value = " a ";
 
-        assertEquals("{\"value\":\"a\"}", JSON.toJSONString(model));
+        assertEquals("{\"value\":\"a\"}", JsonMapper.toJsonString(model));
 
-        Model model2 = JSON.parseObject("{\"value\":\" a \"}", Model.class);
+        Model model2 = JsonMapper.parseJsonObject("{\"value\":\" a \"}", Model.class);
         assertEquals("a", model2.value);
     }
 
@@ -30,7 +29,7 @@ public class Issue1310 {
         Model2 model = new Model2();
         model.value = " a ";
 
-        assertEquals("{\"value\":\"a\"}", JSON.toJSONString(model));
+        assertEquals("{\"value\":\"a\"}", JsonMapper.toJsonString(model));
 
         ObjectReader<Model2> objectReader = ObjectReaderCreatorLambda.INSTANCE.createObjectReader(Model2.class);
         JSONReader jsonReader = JSONReader.of("{\"value\":\" a \"}");
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1310_noasm.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1310_noasm.java
index e8c811c4d..650c7dce2 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1310_noasm.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1310_noasm.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -17,9 +16,9 @@ public class Issue1310_noasm {
         Model model = new Model();
         model.value = " a ";
 
-        assertEquals("{\"value\":\"a\"}", JSON.toJSONString(model));
+        assertEquals("{\"value\":\"a\"}", JsonMapper.toJsonString(model));
 
-        Model model2 = JSON.parseObject("{\"value\":\" a \"}", Model.class);
+        Model model2 = JsonMapper.parseJsonObject("{\"value\":\" a \"}", Model.class);
         assertEquals("a", model2.value);
     }
 
@@ -28,9 +27,9 @@ public class Issue1310_noasm {
         Model1 model = new Model1();
         model.value = " a ";
 
-        assertEquals("{\"value\":\"a\"}", JSON.toJSONString(model));
+        assertEquals("{\"value\":\"a\"}", JsonMapper.toJsonString(model));
 
-        Model1 model2 = JSON.parseObject("{\"value\":\" a \"}", Model1.class);
+        Model1 model2 = JsonMapper.parseJsonObject("{\"value\":\" a \"}", Model1.class);
         assertEquals("a", model2.value);
     }
 
@@ -39,9 +38,9 @@ public class Issue1310_noasm {
         Model2 model = new Model2(1);
         model.value = " a ";
 
-        assertEquals("{\"id\":1,\"value\":\"a\"}", JSON.toJSONString(model));
+        assertEquals("{\"id\":1,\"value\":\"a\"}", JsonMapper.toJsonString(model));
 
-        Model2 model2 = JSON.parseObject("{\"value\":\" a \"}", Model2.class);
+        Model2 model2 = JsonMapper.parseJsonObject("{\"value\":\" a \"}", Model2.class);
         assertEquals("a", model2.value);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1335.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1335.java
index 3edd84722..9da727989 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1335.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1335.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -23,7 +22,7 @@ public class Issue1335 {
                 "\"original_save_url\": \"http://hl-img.peco.uodoo.com/hubble-test/app/sm/e9b884c1dcd671f128bac020e070e273.jpg\",\n" +
                 "\"phash\": \"62717D190987A7AE\"\n" +
                 "                            }";
-        Image image = JSON.parseObject(json, Image.class, JSONReader.Feature.SupportSmartMatch);
+        Image image = JsonMapper.parseJsonObject(json, Image.class, JSONReader.Feature.SupportSmartMatch);
         assertEquals("21496a63f5", image.id);
         assertEquals("http://hl-img.peco.uodoo.com/hubble-test/app/sm/e9b884c1dcd671f128bac020e070e273.jpg;,,JPG;3,208x", image.url);
         assertEquals("", image.title);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1344.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1344.java
index 6bcac5b71..f4ee0b7d1 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1344.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1344.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 /**
@@ -13,9 +12,9 @@ public class Issue1344 {
     public void test_for_issue() throws Exception {
         TestException testException = new TestException("aaa");
         System.out.println("before：" + testException.getMessage());
-        String json = JSON.toJSONString(testException);
+        String json = JsonMapper.toJsonString(testException);
         System.out.println(json);
-        TestException o = JSON.parseObject(json, TestException.class);
+        TestException o = JsonMapper.parseJsonObject(json, TestException.class);
         System.out.println("after：" + o.getMessage());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1357.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1357.java
index 39440402a..b7af1451a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1357.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1357.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.time.LocalDateTime;
@@ -14,7 +13,7 @@ public class Issue1357 {
     public void test_for_issue() throws Exception {
 
         String str = "{\"d2\":null}";
-        Test2Bean b = JSON.parseObject(str,Test2Bean.class);
+        Test2Bean b = JsonMapper.parseJsonObject(str,Test2Bean.class);
         System.out.println(b);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1363.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1363.java
index 30131ecb1..72ab4a439 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1363.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1363.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -24,10 +23,10 @@ public class Issue1363 {
         map.put(a.name, a);
         b.value1 = map;
 
-        String jsonStr = JSON.toJSONString(b);
+        String jsonStr = JsonMapper.toJsonString(b);
         System.out.println(jsonStr);
-        DataSimpleVO obj = JSON.parseObject(jsonStr, DataSimpleVO.class);
-        assertEquals(jsonStr, JSON.toJSONString(obj));
+        DataSimpleVO obj = JsonMapper.parseJsonObject(jsonStr, DataSimpleVO.class);
+        assertEquals(jsonStr, JsonMapper.toJsonString(obj));
     }
 
     @Test
@@ -39,12 +38,12 @@ public class Issue1363 {
         map.put(a.name, a);
         b.value = map;
 
-        String jsonStr = JSON.toJSONString(b);
+        String jsonStr = JsonMapper.toJsonString(b);
         System.out.println(jsonStr);
-        DataSimpleVO obj = JSON.parseObject(jsonStr, DataSimpleVO.class);
+        DataSimpleVO obj = JsonMapper.parseJsonObject(jsonStr, DataSimpleVO.class);
         System.out.println(obj.toString());
         assertNotNull(obj.value1);
-        assertEquals(jsonStr, JSON.toJSONString(obj));
+        assertEquals(jsonStr, JsonMapper.toJsonString(obj));
     }
 
     public static class DataSimpleVO {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1369.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1369.java
index c32cc0460..33abc9cb9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1369.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1369.java
@@ -1,8 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
-import org.junit.Assert;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertTrue;
@@ -18,7 +16,7 @@ public class Issue1369 {
         foo.b = "b";
         foo.bars = new Bar();
         foo.bars.c = 3;
-        String json = JSON.toJSONString(foo);
+        String json = JsonMapper.toJsonString(foo);
         System.out.println(json);
         assertTrue(json.indexOf("\\")<0);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1371.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1371.java
index 6eadf39a7..ee63bf9a6 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1371.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1371.java
@@ -1,8 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
-import org.junit.Assert;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Map;
@@ -26,7 +24,7 @@ public class Issue1371 {
         enumMap.put(Rooms.C, Rooms.D);
         enumMap.put(Rooms.E, Rooms.A);
 
-        assertEquals(JSON.toJSONString(enumMap),
+        assertEquals(JsonMapper.toJsonString(enumMap),
                 "{\"C\":\"D\",\"E\":\"A\"}");
 
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1399.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1399.java
index 9457b2a78..beecef43c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1399.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue1399.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 /**
@@ -10,27 +9,27 @@ import org.junit.jupiter.api.Test;
 public class Issue1399 {
     @Test
     public void test_for_issue() throws Exception {
-        JSON.parseObject("false", boolean.class);
-        JSON.parseObject("false", Boolean.class);
-        JSON.parseObject("\"false\"", boolean.class);
-        JSON.parseObject("\"false\"", Boolean.class);
+        JsonMapper.parseJsonObject("false", boolean.class);
+        JsonMapper.parseJsonObject("false", Boolean.class);
+        JsonMapper.parseJsonObject("\"false\"", boolean.class);
+        JsonMapper.parseJsonObject("\"false\"", Boolean.class);
 
 //        JSON.parseObject("FALSE", boolean.class);
 //        JSON.parseObject("FALSE", Boolean.class);
-        JSON.parseObject("\"FALSE\"", boolean.class);
-        JSON.parseObject("\"FALSE\"", Boolean.class);
+        JsonMapper.parseJsonObject("\"FALSE\"", boolean.class);
+        JsonMapper.parseJsonObject("\"FALSE\"", Boolean.class);
     }
 
     @Test
     public void test_for_issue_true() throws Exception {
-        JSON.parseObject("true", boolean.class);
-        JSON.parseObject("true", Boolean.class);
-        JSON.parseObject("\"true\"", boolean.class);
-        JSON.parseObject("\"true\"", Boolean.class);
+        JsonMapper.parseJsonObject("true", boolean.class);
+        JsonMapper.parseJsonObject("true", Boolean.class);
+        JsonMapper.parseJsonObject("\"true\"", boolean.class);
+        JsonMapper.parseJsonObject("\"true\"", Boolean.class);
 
 //        JSON.parseObject("FALSE", boolean.class);
 //        JSON.parseObject("FALSE", Boolean.class);
-        JSON.parseObject("\"TRUE\"", boolean.class);
-        JSON.parseObject("\"TRUE\"", Boolean.class);
+        JsonMapper.parseJsonObject("\"TRUE\"", boolean.class);
+        JsonMapper.parseJsonObject("\"TRUE\"", Boolean.class);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue_for_zuojian.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue_for_zuojian.java
index 1886a5e9a..5789a78eb 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue_for_zuojian.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1300/Issue_for_zuojian.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Date;
@@ -12,7 +11,7 @@ public class Issue_for_zuojian {
     @Test
     public void test_for_issue() throws Exception {
         String json = "{\"value\":\"20180131022733000-0800\"}";
-        Model model = JSON.parseObject(json, Model.class, "yyyyMMddHHmmssSSSZ");
+        Model model = JsonMapper.parseJsonObject(json, Model.class, "yyyyMMddHHmmssSSSZ");
         assertNotNull(model.value);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1400.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1400.java
index a236fb7c3..5db7042b8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1400.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1400.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.TypeReference;
 import org.junit.Assert;
 import org.junit.jupiter.api.Test;
@@ -39,7 +39,7 @@ public class Issue1400 {
         String str = "{\"ret\":1,\"message\":\"ok\",\"data\":[{\"appId\":\"11c53f541dee4f5bbc4f75f99002278c\"},{\"appId\":\"c6102275ce5540a59424defa1cccb8ed\"}]}";
         public Resource resource;
         Bean(TypeReference tr) {
-            resource = (Resource)JSON.parseObject(str, tr.getType());
+            resource = (Resource) JsonMapper.parseJsonObject(str, tr.getType());
         }
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1422.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1422.java
index 0e93f5a4c..20dca26fe 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1422.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1422.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertFalse;
@@ -11,14 +10,14 @@ public class Issue1422 {
     public void test_for_issue() throws Exception {
         String strOk = "{\"v\": 111}";
 
-        Foo ok = JSON.parseObject(strOk, Foo.class);
+        Foo ok = JsonMapper.parseJsonObject(strOk, Foo.class);
         assertFalse(ok.v);
     }
 
     @Test
     public void test_for_issue_1() throws Exception {
         String strBad = "{\"v\":111}";
-        Foo bad = JSON.parseObject(strBad, Foo.class);
+        Foo bad = JsonMapper.parseJsonObject(strBad, Foo.class);
         assertFalse(bad.v);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1424.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1424.java
index ead2b38ac..9c6b06fb9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1424.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1424.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -43,11 +42,11 @@ public class Issue1424 {
         Map<String, Long> intOverflowMap = new HashMap<String, Long>();
         long intOverflow = Integer.MAX_VALUE;
         intOverflowMap.put("v", intOverflow + 1);
-        String sIntOverflow = JSON.toJSONString(intOverflowMap);
+        String sIntOverflow = JsonMapper.toJsonString(intOverflowMap);
 
         Exception error = null;
         try {
-            JSON.parseObject(sIntOverflow, IntegerVal.class);
+            JsonMapper.parseJsonObject(sIntOverflow, IntegerVal.class);
         } catch (Exception e) {
             error = e;
         }
@@ -59,10 +58,10 @@ public class Issue1424 {
         Map<String, Double> floatOverflowMap = new HashMap<String, Double>();
         double floatOverflow = Float.MAX_VALUE;
         floatOverflowMap.put("v", floatOverflow + 1);
-        String sFloatOverflow = JSON.toJSONString(floatOverflowMap);
+        String sFloatOverflow = JsonMapper.toJsonString(floatOverflowMap);
 
         assertEquals("{\"v\":3.4028234663852886E38}", sFloatOverflow);
-        FloatVal floatVal = JSON.parseObject(sFloatOverflow, FloatVal.class);
+        FloatVal floatVal = JsonMapper.parseJsonObject(sFloatOverflow, FloatVal.class);
         assertEquals(3.4028235E38F, floatVal.v);
 
         assertEquals(floatVal.v, Float.parseFloat("3.4028234663852886E38"));
@@ -73,11 +72,11 @@ public class Issue1424 {
         Map<String, Double> floatOverflowMap = new HashMap<String, Double>();
         double floatOverflow = Float.MAX_VALUE;
         floatOverflowMap.put("v", floatOverflow + floatOverflow);
-        String sFloatOverflow = JSON.toJSONString(floatOverflowMap);
+        String sFloatOverflow = JsonMapper.toJsonString(floatOverflowMap);
 
         System.out.println(sFloatOverflow);
         assertEquals("{\"v\":6.805646932770577E38}", sFloatOverflow);
-        FloatVal floatVal = JSON.parseObject(sFloatOverflow, FloatVal.class);
+        FloatVal floatVal = JsonMapper.parseJsonObject(sFloatOverflow, FloatVal.class);
         assertEquals(Float.parseFloat("6.805646932770577E38"), floatVal.v);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1425.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1425.java
index 441ac2fc2..1be470bbd 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1425.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1425.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 public class Issue1425 {
@@ -17,7 +16,7 @@ public class Issue1425 {
                 JSONWriter.Feature.WriteClassName
         };
 
-        System.out.println(JSON.toJSONString(dicDomain, features));
+        System.out.println(JsonMapper.toJsonString(dicDomain, features));
     }
     public static class DicDomain {
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1443.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1443.java
index e0a9cffc5..91602acea 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1443.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1443.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Date;
@@ -10,7 +9,7 @@ public class Issue1443 {
     @Test
     public void test_for_issue() throws Exception {
         String json = "{\"date\":\"3017-08-28T00:00:00+08:00\"}";
-        Model model = JSON.parseObject(json, Model.class);
+        Model model = JsonMapper.parseJsonObject(json, Model.class);
 
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1445.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1445.java
index c631fc897..20123ac53 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1445.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1445.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 public class Issue1445 {
@@ -15,7 +14,7 @@ public class Issue1445 {
         obj.getJSONObject("data").getJSONObject("data").put("map", new JSONObject());
         obj.getJSONObject("data").getJSONObject("data").getJSONObject("map").put("21160001", "abc");
 
-        String json = JSON.toJSONString(obj);
+        String json = JsonMapper.toJsonString(obj);
 //        assertEquals("abc", JSONPath.read(json,"data.data.map.21160001"));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1450.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1450.java
index 0b2230d9e..8dc17340c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1450.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1450.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.time.LocalDateTime;
@@ -12,7 +11,7 @@ public class Issue1450 {
     @Test
     public void test_for_issue() throws Exception {
         LocalDateTime localDateTime = LocalDateTime.of(2018, 8, 31, 15, 26, 37, 1);
-        String json = JSON.toJSONString(localDateTime, "yyyy-MM-dd HH:mm:ss");//2018-08-31T15:26:37.000000001
+        String json = JsonMapper.toJsonString(localDateTime, "yyyy-MM-dd HH:mm:ss");//2018-08-31T15:26:37.000000001
         assertEquals("\"2018-08-31 15:26:37\"", json);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1458.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1458.java
index 2ea113c49..6b292c46e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1458.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1458.java
@@ -1,10 +1,9 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
 import com.google.common.collect.ImmutableMap;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.io.Serializable;
@@ -17,10 +16,10 @@ public class Issue1458 {
         HostPoint hostPoint = new HostPoint(new HostAddress("192.168.10.101"));
         hostPoint.setFingerprint(new Fingerprint("abc"));
 
-        String json = JSON.toJSONString(hostPoint);
+        String json = JsonMapper.toJsonString(hostPoint);
 
-        HostPoint hostPoint1 = JSON.parseObject(json, HostPoint.class);
-        String json1 = JSON.toJSONString(hostPoint1);
+        HostPoint hostPoint1 = JsonMapper.parseJsonObject(json, HostPoint.class);
+        String json1 = JsonMapper.toJsonString(hostPoint1);
         assertEquals(json, json1);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1458C.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1458C.java
index 2dd7e0909..0c94a9f7c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1458C.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1458C.java
@@ -1,10 +1,9 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson.annotation.JSONCreator;
 import com.alibaba.fastjson.annotation.JSONField;
 import com.google.common.collect.ImmutableMap;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.io.Serializable;
@@ -17,10 +16,10 @@ public class Issue1458C {
         HostPoint hostPoint = new HostPoint(new HostAddress("192.168.10.101"));
         hostPoint.setFingerprint(new Fingerprint("abc"));
 
-        String json = JSON.toJSONString(hostPoint);
+        String json = JsonMapper.toJsonString(hostPoint);
 
-        HostPoint hostPoint1 = JSON.parseObject(json, HostPoint.class);
-        String json1 = JSON.toJSONString(hostPoint1);
+        HostPoint hostPoint1 = JsonMapper.parseJsonObject(json, HostPoint.class);
+        String json1 = JsonMapper.toJsonString(hostPoint1);
         assertEquals(json, json1);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1465.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1465.java
index 99e2348d3..262ccda03 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1465.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1465.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -10,7 +10,7 @@ public class Issue1465 {
     @Test
     public void test_for_issue() throws Exception {
         String json = "{\"id\":3,\"hasSth\":true}";
-        Model model = JSON.parseObject(json, Model.class);
+        Model model = JsonMapper.parseJsonObject(json, Model.class);
         assertEquals(0, model.hasSth);
         assertEquals(3, model.id);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1474.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1474.java
index 2d61d1a4a..519f8017f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1474.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1474.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -22,7 +21,7 @@ public class Issue1474 {
         p.setName("顾客");
         p.setExtraData(extraData);
 
-        assertEquals("{\"id\":\"001\",\"name\":\"顾客\"}", JSON.toJSONString(p));
+        assertEquals("{\"id\":\"001\",\"name\":\"顾客\"}", JsonMapper.toJsonString(p));
     }
 
     static class People{
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1478.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1478.java
index fed12f9c5..e41defdd8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1478.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1478.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,7 +11,7 @@ public class Issue1478 {
         Model model = new Model();
         model.md5 = "xxx";
 
-        String json = JSON.toJSONString(model);
+        String json = JsonMapper.toJsonString(model);
         assertEquals("{\"MD5\":\"xxx\"}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1482.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1482.java
index 1e181db64..9f92ad8ba 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1482.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1482.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Date;
@@ -9,7 +8,7 @@ import java.util.Date;
 public class Issue1482 {
     @Test
     public void test_for_issue() throws Exception {
-        JSON.parseObject("{\"date\":\"2017-06-28T07:20:05.000+05:30\"}", Model.class);
+        JsonMapper.parseJsonObject("{\"date\":\"2017-06-28T07:20:05.000+05:30\"}", Model.class);
     }
 
     public static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1486.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1486.java
index ac677a86c..dea787bda 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1486.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1486.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import com.alibaba.fastjson2.TypeReference;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.List;
@@ -13,7 +12,7 @@ public class Issue1486 {
     public void test_for_issue() throws Exception {
 
         String json = "[{\"song_list\":[{\"val\":1,\"v_al\":2},{\"val\":2,\"v_al\":2},{\"val\":3,\"v_al\":2}],\"songlist\":\"v_al\"}]";
-        List<Value> parseObject = JSON.parseObject(json, new TypeReference<List<Value>>() {
+        List<Value> parseObject = JsonMapper.parseJsonObject(json, new TypeReference<List<Value>>() {
         }.getType());
         for (Value value : parseObject) {
             System.out.println(value.songList + "  " );
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1487.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1487.java
index 57a9210b8..567cd0508 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1487.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1487.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -14,10 +13,10 @@ public class Issue1487 {
         model._id = 1001L;
         model.id = 1002L;
 
-        String json = JSON.toJSONString(model);
+        String json = JsonMapper.toJsonString(model);
         assertEquals("{\"_id\":1001,\"id\":1002}", json);
-        Model model1 = JSON.parseObject(json, Model.class);
-        assertEquals(json, JSON.toJSONString(model1));
+        Model model1 = JsonMapper.parseJsonObject(json, Model.class);
+        assertEquals(json, JsonMapper.toJsonString(model1));
     }
 
     public static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1492.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1492.java
index a13e0406d..f39bd7c97 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1492.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1492.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONArray;
 import com.alibaba.fastjson2.JSONObject;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.io.Serializable;
@@ -21,10 +20,10 @@ public class Issue1492 {
         obj.put("key2","value2");
         resp.setData(obj);
 
-        String str = JSON.toJSONString(resp);
+        String str = JsonMapper.toJsonString(resp);
         System.out.println(str);
-        DubboResponse resp1 = JSON.parseObject(str, DubboResponse.class);
-        assertEquals(str, JSON.toJSONString(resp1));
+        DubboResponse resp1 = JsonMapper.parseJsonObject(str, DubboResponse.class);
+        assertEquals(str, JsonMapper.toJsonString(resp1));
 
         // test for JSONArray
         JSONArray arr = new JSONArray();
@@ -32,10 +31,10 @@ public class Issue1492 {
         arr.add("key2");
         resp.setData(arr);
 
-        String str2 = JSON.toJSONString(resp);
+        String str2 = JsonMapper.toJsonString(resp);
         System.out.println(str2);
-        DubboResponse resp2 = JSON.parseObject(str2, DubboResponse.class);
-        assertEquals(str2, JSON.toJSONString(resp2));
+        DubboResponse resp2 = JsonMapper.parseJsonObject(str2, DubboResponse.class);
+        assertEquals(str2, JsonMapper.toJsonString(resp2));
 
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1493.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1493.java
index 0e9bd8fb5..230088a64 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1493.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1493.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import org.junit.Assert;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.time.LocalDateTime;
@@ -24,9 +23,9 @@ public class Issue1493 {
         LocalDateTime time2 = LocalDateTime.parse(stime2);
         test.setTime1(time1);
         test.setTime2(time2);
-        String t1 = JSON.toJSONString(time1);
+        String t1 = JsonMapper.toJsonString(time1);
 
-        String json = JSON.toJSONString(test);
+        String json = JsonMapper.toJsonString(test);
         assertEquals("{\"time1\":"+t1+",\"time2\":\"2017-09-22T15:08:56\"}",json);
 
 
@@ -34,14 +33,14 @@ public class Issue1493 {
         //JSON.DEFFAULT_LOCAL_DATE_TIME_FORMAT = "yyyy-MM-dd HH:mm:ss";
         //String stime1 = DateTimeFormatter.ofPattern(JSON.DEFFAULT_LOCAL_DATE_TIME_FORMAT, Locale.CHINA).format(time1);
 
-        json = JSON.toJSONString(test);
-        assertEquals("{\"time1\":"+ JSON.toJSONString(time1) +",\"time2\":\"2017-09-22T15:08:56\"}",json);
+        json = JsonMapper.toJsonString(test);
+        assertEquals("{\"time1\":"+ JsonMapper.toJsonString(time1) +",\"time2\":\"2017-09-22T15:08:56\"}",json);
 
 
         String pattern = "yyyy-MM-dd'T'HH:mm:ss";
         String stime1 = DateTimeFormatter.ofPattern(pattern, Locale.CHINA).format(time1);
 
-        json = JSON.toJSONString(test, "yyyy-MM-dd'T'HH:mm:ss");
+        json = JsonMapper.toJsonString(test, "yyyy-MM-dd'T'HH:mm:ss");
         assertEquals("{\"time1\":\""+stime1+"\",\"time2\":\""+stime2+"\"}",json);
 
         //JSON.DEFFAULT_LOCAL_DATE_TIME_FORMAT = default_format;
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1496.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1496.java
index 1fee8b23e..676b4779d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1496.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1496.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONType;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.Arrays;
@@ -13,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1496 {
     @Test
     public void test_for_issue() throws Exception {
-        String json = JSON.toJSONString(SetupStatus.FINAL_TRAIL);
+        String json = JsonMapper.toJsonString(SetupStatus.FINAL_TRAIL);
         assertEquals("{\"canRefuse\":true,\"code\":3,\"name\":\"FINAL_TRAIL\",\"nameCn\":\"公益委员会/理事会/理事长审核\"}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1498.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1498.java
index 9098e160e..bea8b06f4 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1498.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue1498.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertNull;
@@ -10,13 +9,13 @@ import static org.junit.jupiter.api.Assertions.assertSame;
 public class Issue1498 {
     @Test
     public void test_for_issue() throws Exception {
-        Model model = JSON.parseObject("{\"flag\":\"QUALITY_GRADUATE\"}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"flag\":\"QUALITY_GRADUATE\"}", Model.class);
         assertNull(model.flag);
     }
 
     @Test
     public void test_for_issue_match() throws Exception {
-        Model model = JSON.parseObject("{\"flag\":\"IS_NEED_CHECK_IDENTITY\"}", Model.class);
+        Model model = JsonMapper.parseJsonObject("{\"flag\":\"IS_NEED_CHECK_IDENTITY\"}", Model.class);
         assertSame(BuFlag.IS_NEED_CHECK_IDENTITY, model.flag);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue_for_wuye.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue_for_wuye.java
index e2b8263c7..00da56115 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue_for_wuye.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1400/Issue_for_wuye.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1400;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Date;
@@ -10,7 +9,7 @@ public class Issue_for_wuye {
     @Test
     public void test_for_issue() throws Exception {
         String poistr = "{\"gmtModified\":\"2017-09-07 16:39:19\",\"gmtCreate\":\"2017-09-07 16:39:19\"}";
-        TimeBean poiInfo = JSON.parseObject(poistr, TimeBean.class);
+        TimeBean poiInfo = JsonMapper.parseJsonObject(poistr, TimeBean.class);
     }
 
     public static class TimeBean {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1500.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1500.java
index 93589d02e..e4da89f8c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1500.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1500.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -14,17 +14,17 @@ public class Issue1500 {
         // test aa
         Aa aa = new Aa();
         aa.setName("aa");
-        String jsonAa = JSON.toJSONString(aa);
+        String jsonAa = JsonMapper.toJsonString(aa);
 //        System.out.println(jsonAa);
 
-        Aa aa1 = JSON.parseObject(jsonAa, Aa.class);
+        Aa aa1 = JsonMapper.parseJsonObject(jsonAa, Aa.class);
         assertEquals("aa",aa1.getName());
 
         // test C
         C c = new C();
         c.setE(aa);
-        String jsonC = JSON.toJSONString(c, JSONWriter.Feature.WriteClassName);
-        C c2 = JSON.parseObject(jsonC, C.class);
+        String jsonC = JsonMapper.toJsonString(c, JSONWriter.Feature.WriteClassName);
+        C c2 = JsonMapper.parseJsonObject(jsonC, C.class);
         assertEquals("Aa",c2.getE().getClass().getSimpleName());
         assertEquals("aa",((Aa)c2.getE()).getName());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1503.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1503.java
index c0af29ea8..9ee911938 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1503.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1503.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -15,8 +15,8 @@ public class Issue1503 {
 //        config.setAutoTypeSupport(true);
         Map<Long, Bean> map = new HashMap<Long, Bean>();
         map.put(null, new Bean());
-        Map<Long, Bean> rmap = (Map<Long, Bean>) JSON.parse(JSON.toJSONString(map, JSONWriter.Feature.WriteClassName));
-        String json = JSON.toJSONString(rmap);
+        Map<Long, Bean> rmap = (Map<Long, Bean>) JsonMapper.parseJson(JsonMapper.toJsonString(map, JSONWriter.Feature.WriteClassName));
+        String json = JsonMapper.toJsonString(rmap);
         assertEquals("{\"null\":{\"@type\":\"com.alibaba.fastjson2.v1issues.issue_1500.Issue1503$Bean\"}}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1510.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1510.java
index 5a65f9872..84e2cdd89 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1510.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1510.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -11,8 +11,8 @@ import static junit.framework.TestCase.assertEquals;
 public class Issue1510 {
     @Test
     public void test_for_issue() throws Exception {
-        Model model = JSON.parseObject("{\"startTime\":\"2017-11-04\",\"endTime\":\"2017-11-14\"}", Model.class);
-        String text = JSON.toJSONString(model);
+        Model model = JsonMapper.parseJsonObject("{\"startTime\":\"2017-11-04\",\"endTime\":\"2017-11-14\"}", Model.class);
+        String text = JsonMapper.toJsonString(model);
         assertEquals("{\"endTime\":\"2017-11-14\",\"startTime\":\"2017-11-04\"}", text);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1513.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1513.java
index cb758eede..744f5ae3b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1513.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1513.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.TypeReference;
 import org.junit.jupiter.api.Test;
@@ -11,28 +11,28 @@ public class Issue1513 {
     @Test
     public void test_for_issue() throws Exception {
         {
-            Model<Object> model = JSON.parseObject("{\"values\":[{\"id\":123}]}", new TypeReference<Model<Object>>(){}.getType());
+            Model<Object> model = JsonMapper.parseJsonObject("{\"values\":[{\"id\":123}]}", new TypeReference<Model<Object>>(){}.getType());
             assertNotNull(model.values);
             assertEquals(1, model.values.length);
             JSONObject object = (JSONObject) model.values[0];
             assertEquals(123, object.getIntValue("id"));
         }
         {
-            Model<A> model = JSON.parseObject("{\"values\":[{\"id\":123}]}", new TypeReference<Model<A>>(){}.getType());
+            Model<A> model = JsonMapper.parseJsonObject("{\"values\":[{\"id\":123}]}", new TypeReference<Model<A>>(){}.getType());
             assertNotNull(model.values);
             assertEquals(1, model.values.length);
             A a = model.values[0];
             assertEquals(123, a.id);
         }
         {
-            Model<B> model = JSON.parseObject("{\"values\":[{\"value\":123}]}", new TypeReference<Model<B>>(){}.getType());
+            Model<B> model = JsonMapper.parseJsonObject("{\"values\":[{\"value\":123}]}", new TypeReference<Model<B>>(){}.getType());
             assertNotNull(model.values);
             assertEquals(1, model.values.length);
             B b = model.values[0];
             assertEquals(123, b.value);
         }
         {
-            Model<C> model = JSON.parseObject("{\"values\":[{\"age\":123}]}", new TypeReference<Model<C>>(){}.getType());
+            Model<C> model = JsonMapper.parseJsonObject("{\"values\":[{\"age\":123}]}", new TypeReference<Model<C>>(){}.getType());
             assertNotNull(model.values);
             assertEquals(1, model.values.length);
             C c = model.values[0];
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1524.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1524.java
index eb6bfde7f..169dc38a5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1524.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1524.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONField;
 import com.alibaba.fastjson2.filter.NameFilter;
@@ -18,7 +18,7 @@ public class Issue1524 {
         Model model = new Model();
         model.oldValue = new Value();
 
-        String json = JSON.toJSONString(model, new NameFilter() {
+        String json = JsonMapper.toJsonString(model, new NameFilter() {
             public String process(Object object, String name, Object value) {
                 if ("oldValue".equals(name)) {
                     return "old_value";
@@ -34,7 +34,7 @@ public class Issue1524 {
         Model1 model = new Model1();
         model.oldValue = new Value();
 
-        String json = JSON.toJSONString(model, new NameFilter() {
+        String json = JsonMapper.toJsonString(model, new NameFilter() {
             public String process(Object object, String name, Object value) {
                 if ("oldValue".equals(name)) {
                     return "old_value";
@@ -50,7 +50,7 @@ public class Issue1524 {
         Model2 model = new Model2();
         model.oldValue = new Value();
 
-        String json = JSON.toJSONString(model, new NameFilter() {
+        String json = JsonMapper.toJsonString(model, new NameFilter() {
             public String process(Object object, String name, Object value) {
                 if ("oldValue".equals(name)) {
                     return "old_value";
@@ -66,7 +66,7 @@ public class Issue1524 {
         Model3 model = new Model3();
         model.oldValue = new Value();
 
-        String json = JSON.toJSONString(model, new NameFilter() {
+        String json = JsonMapper.toJsonString(model, new NameFilter() {
             public String process(Object object, String name, Object value) {
                 if ("oldValue".equals(name)) {
                     return "old_value";
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1529.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1529.java
index 40c29277a..c937afa39 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1529.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1529.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import org.junit.jupiter.api.Test;
 
@@ -10,7 +10,7 @@ public class Issue1529 {
     @Test
     public void test_for_issue() throws Exception {
         String text = "{\"isId\":false,\"Id\":138042533,\"name\":\"example\",\"height\":172}";
-        Person person = JSON.parseObject(text, Person.class, JSONReader.Feature.SupportSmartMatch);
+        Person person = JsonMapper.parseJsonObject(text, Person.class, JSONReader.Feature.SupportSmartMatch);
         assertEquals(138042533, person.Id);
         assertEquals("example", person.name);
         assertEquals(172.0D, person.height);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1548.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1548.java
index 48e414110..a89784d57 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1548.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1548.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -12,7 +12,7 @@ public class Issue1548 {
     public void test_for_issue() throws Exception {
         String msg = "[{\"doc\":{\"bottomprice\":80,\"cashpool_isdeleted\":0,\"shopcityid\":190,\"timerange\":\"2017-10-25;2017-10-26\",\"launchentityid\":3048,\"bidprice\":700,\"targetitems\":\"{}\",\"type\":0,\"slottagid\":44,\"targetid\":330048,\"entity_isdeleted\":0,\"bu\":2,\"target_isdeleted\":0,\"shopid\":6067941,\"slotids\":\"50041,10233,50051,10033,50061,50001,10099,10133,50101,10051\",\"launchscope\":0,\"productid\":74,\"creativeid\":300048,\"dpentitystatus\":1,\"accountid\":20151002,\"entitytype\":4,\"launchplatforms\":\"\",\"iszhuantou\":0,\"dpentityid\":6067941,\"timeslotperiod\":\"0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160,161,162,163,164,165,166,167\",\"templateid\":23,\"category1\":246,\"launch_isdeleted\":0,\"cashpoolid\":20151002,\"creative_isdeleted\":0,\"settlementstatus\":1,\"cityid\":\"190\",\"planid\":1042007,\"categoryid\":\"10 246\",\"price\":700,\"shoptype\":10,\"plan_isdeleted\":0,\"launchid\":30000048,\"creativeext\":\"{\\\"content\\\":\\\"啊啊啊啊啊啊啊啊\\\",\\\"title\\\":\\\"啊啊啊啊啊\\\",\\\"smartPic\\\":0,\\\"mobUrl\\\":\\\"https://evt.dianping.com/midas/1activities/3809/index.html?dpid=7997757988618737578&cityid=1&longitude=121.41543&latitude=31.21684&token=&product=dpapp&area=pc\\\",\\\"mtMobUrl\\\":\\\"https://evt.dianping.com/midas/1activities/3809/index.html?dpid=7997757988618737578&cityid=1&longitude=121.41543&latitude=31.21684&token=&product=dpapp&area=mtapp\\\"}\",\"chargetype\":1,\"channel\":0,\"generatedchannel\":0,\"promotype\":2},\"meta\":{\"LSN\":2077395,\"AREA\":\"engine-searchcpc\",\"PRIMARY_KEY\":[\"creativeid\",\"targetid\"],\"SECONDARY_KEY\":[\"planid\",\"shopid\",\"launchentityid\",\"launchid\",\"cashpoolid\"],\"TYPE\":\"UPDATE\"}}]";
         // JSONArray.parse(msg);
-        JSON.parseArray(msg).toJavaList(PublishDoc.class);
+        JsonMapper.parseJsonArray(msg).toJavaList(PublishDoc.class);
     }
 
     public static class PublishDoc implements Serializable {
@@ -45,7 +45,7 @@ public class Issue1548 {
 
         @Override
         public String toString() {
-            return JSON.toJSONString(this);
+            return JsonMapper.toJsonString(this);
         }
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1555.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1555.java
index 3eb89e27f..4e596ba7d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1555.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1555.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.NamingStrategy;
 import com.alibaba.fastjson2.annotation.JSONField;
 import com.alibaba.fastjson2.annotation.JSONType;
@@ -14,10 +14,10 @@ public class Issue1555 {
         Model model = new Model();
         model.userId = 1001;
         model.userName = "test";
-        String text = JSON.toJSONString(model);
+        String text = JsonMapper.toJsonString(model);
         assertEquals("{\"userName\":\"test\",\"user_id\":1001}", text);
 
-        Model model2 = JSON.parseObject(text, Model.class);
+        Model model2 = JsonMapper.parseJsonObject(text, Model.class);
 
         assertEquals(1001, model2.userId);
         assertEquals("test", model2.userName);
@@ -31,10 +31,10 @@ public class Issue1555 {
         ModelTwo modelTwo = new ModelTwo();
         modelTwo.userId = 1001;
         modelTwo.userName = "test";
-        String text = JSON.toJSONString(modelTwo);
+        String text = JsonMapper.toJsonString(modelTwo);
         assertEquals("{\"userName\":\"test\",\"user_id\":\"1001\"}", text);
 
-        Model model2 = JSON.parseObject(text, Model.class);
+        Model model2 = JsonMapper.parseJsonObject(text, Model.class);
 
         assertEquals(1001, model2.userId);
         assertEquals("test", model2.userName);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1556.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1556.java
index 508fa661f..13bf1cf09 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1556.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1556.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -28,10 +28,10 @@ public class Issue1556 {
         ApiResult<ClassForData> apiResult = ApiResult.valueOfSuccess(classForData);
 //        config.setAutoTypeSupport(true);
 
-        String jsonString = JSON.toJSONString(apiResult, JSONWriter.Feature.WriteClassName);//这里加上SerializerFeature.DisableCircularReferenceDetect
+        String jsonString = JsonMapper.toJsonString(apiResult, JSONWriter.Feature.WriteClassName);//这里加上SerializerFeature.DisableCircularReferenceDetect
         System.out.println(jsonString);
-        Object obj = JSON.parse(jsonString);//这里加上Feature.DisableCircularReferenceDetect  这样的话 是可以避免空值的  ，但是$ref 还有啥意思呢
-        System.out.println(JSON.toJSONString(obj));
+        Object obj = JsonMapper.parseJson(jsonString);//这里加上Feature.DisableCircularReferenceDetect  这样的话 是可以避免空值的  ，但是$ref 还有啥意思呢
+        System.out.println(JsonMapper.toJsonString(obj));
     }
 
     public static class ApiResult<T> implements Serializable {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1558.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1558.java
index e131e626e..9d351f18f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1558.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1558.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONType;
 import org.junit.jupiter.api.Test;
 
@@ -10,7 +10,7 @@ public class Issue1558 {
     @Test
     public void test_for_issue() throws Exception {
         String text = "{\"id\": \"439a3213-e734-4bf3-9870-2c471f43d651\", \"instance\": \"v1\", \"interface\": \"com.xxx.aplan.UICommands\", \"method\": \"start\", \"params\": [\"tony\"], \"@type\": \"com.alibaba.json.bvt.issue_1500.Issue1558$Request\"}";
-        JSON.parseObject(text, Request.class);
+        JsonMapper.parseJsonObject(text, Request.class);
     }
 
     @JSONType
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1565.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1565.java
index 128ac5265..1a38b8bc6 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1565.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1565.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.annotation.JSONType;
 import com.alibaba.fastjson2.annotation.NamingStrategy;
@@ -30,8 +30,8 @@ public class Issue1565 {
         expectedBean.setNetValueDate(20171105);
         String expectedStr = "{\"id\":\"S35669\",\"net_value_date\":20171105}";
 
-        String actualStr = JSON.toJSONString(expectedBean);
-        JSONObject actualBean = JSON.parseObject(actualStr);
+        String actualStr = JsonMapper.toJsonString(expectedBean);
+        JSONObject actualBean = JsonMapper.parseJsonObject(actualStr);
         Assert.assertEquals(expectedStr, actualStr);
         Assert.assertEquals(expectedBean.getId(), actualBean.getString("id"));
         Assert.assertEquals(expectedBean.getNetValueDate(), actualBean.getInteger("net_value_date"));
@@ -3406,4 +3406,4 @@ public class Issue1565 {
             this.tagId = tagId;
         }
     }
-}
\ No newline at end of file
+}
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1570.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1570.java
index e26cca761..d150e1833 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1570.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1570.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -12,43 +12,43 @@ public class Issue1570 {
     @Test
     public void test_for_issue() throws Exception {
         Model model = new Model();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":\"\"}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":\"\"}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_string() throws Exception {
         ModelString model = new ModelString();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":\"\"}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":\"\"}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_int() throws Exception {
         ModelInt model = new ModelInt();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":0}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":0}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_long() throws Exception {
         ModelLong model = new ModelLong();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":0}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":0}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_bool() throws Exception {
         ModelBool model = new ModelBool();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":false}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":false}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_list() throws Exception {
         ModelList model = new ModelList();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":[]}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":[]}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     public static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1570_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1570_private.java
index a1710edc5..2e9117215 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1570_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1570_private.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
 
@@ -12,36 +12,36 @@ public class Issue1570_private {
     @Test
     public void test_for_issue() throws Exception {
         Model model = new Model();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":\"\"}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":\"\"}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_int() throws Exception {
         ModelInt model = new ModelInt();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":0}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":0}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_long() throws Exception {
         ModelLong model = new ModelLong();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":0}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":0}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_bool() throws Exception {
         ModelBool model = new ModelBool();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":false}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":false}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     @Test
     public void test_for_issue_list() throws Exception {
         ModelList model = new ModelList();
-        assertEquals("{}", JSON.toJSONString(model));
-        assertEquals("{\"value\":[]}", JSON.toJSONString(model, JSONWriter.Feature.NullAsDefaultValue));
+        assertEquals("{}", JsonMapper.toJsonString(model));
+        assertEquals("{\"value\":[]}", JsonMapper.toJsonString(model, JSONWriter.Feature.NullAsDefaultValue));
     }
 
     private static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1576.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1576.java
index bda959b35..2a68e07f8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1576.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1576.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.ArrayList;
@@ -12,7 +12,7 @@ public class Issue1576 {
     @Test
     public void test_for_issue() throws Exception {
         String json = "{\"code\":200,\"in_msg\":\"a\",\"out_msg\":\"a\",\"data\":[{\"title\":\"a\",\"url\":\"url\",\"content\":\"content\"}],\"client_id\":0,\"client_param\":0,\"userid\":0}";
-        NewsDetail newsDetail = JSON.parseObject(json, NewsDetail.class);
+        NewsDetail newsDetail = JsonMapper.parseJsonObject(json, NewsDetail.class);
         assertNotNull(newsDetail);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1580.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1580.java
index 9fe2dbdba..56ff28341 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1580.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1580.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.filter.Filter;
 import com.alibaba.fastjson2.filter.SimplePropertyPreFilter;
@@ -18,7 +18,7 @@ public class Issue1580 {
         model.code = 1001;
         model.name = "N1";
 
-        String json = JSON.toJSONString(model, filters, JSONWriter.Feature.BeanToArray );
+        String json = JsonMapper.toJsonString(model, filters, JSONWriter.Feature.BeanToArray );
         assertEquals("[1001,null]", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1580_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1580_private.java
index 0ab09c821..1f3e6c9d5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1580_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1580_private.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.filter.Filter;
 import com.alibaba.fastjson2.filter.SimplePropertyPreFilter;
@@ -18,7 +18,7 @@ public class Issue1580_private {
         model.code = 1001;
         model.name = "N1";
 
-        String json = JSON.toJSONString(model, filters, JSONWriter.Feature.BeanToArray );
+        String json = JsonMapper.toJsonString(model, filters, JSONWriter.Feature.BeanToArray );
         assertEquals("[1001,null]", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1582.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1582.java
index aa59a9438..29ac1024f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1582.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1582.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -11,17 +11,17 @@ import static junit.framework.TestCase.assertSame;
 public class Issue1582 {
     @Test
     public void test_for_issue() throws Exception {
-        assertSame(Size.Big, JSON.parseObject("\"Big\"", Size.class));
-        assertSame(Size.Big, JSON.parseObject("\"big\"", Size.class));
-        assertNull(JSON.parseObject("\"Large\"", Size.class));
-        assertSame(Size.LL, JSON.parseObject("\"L3\"", Size.class));
+        assertSame(Size.Big, JsonMapper.parseJsonObject("\"Big\"", Size.class));
+        assertSame(Size.Big, JsonMapper.parseJsonObject("\"big\"", Size.class));
+        assertNull(JsonMapper.parseJsonObject("\"Large\"", Size.class));
+        assertSame(Size.LL, JsonMapper.parseJsonObject("\"L3\"", Size.class));
 
-        assertSame(Size.Small, JSON.parseObject("\"Little\"", Size.class));
+        assertSame(Size.Small, JsonMapper.parseJsonObject("\"Little\"", Size.class));
     }
 
     @Test
     public void test_for_issue_1() throws Exception {
-        JSONObject object = JSON.parseObject("{\"size\":\"Little\"}");
+        JSONObject object = JsonMapper.parseJsonObject("{\"size\":\"Little\"}");
         Model model = object.toJavaObject(Model.class);
         assertSame(Size.Small, model.size);
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1583.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1583.java
index 3c3fdb015..3e76e0c46 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1583.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1583.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.TypeReference;
 import org.junit.jupiter.api.Test;
 
@@ -21,10 +21,10 @@ public class Issue1583 {
             totalMap.put("map" + i, list);
         }
         List<Map.Entry<String, List<String>>> mapList = new ArrayList<Map.Entry<String, List<String>>>(totalMap.entrySet());
-        String jsonString = JSON.toJSONString(mapList);
+        String jsonString = JsonMapper.toJsonString(mapList);
 
         System.out.println(jsonString);
-        List<Map.Entry<String, List<String>>> parse = JSON.parseObject(jsonString, new TypeReference<List<Map.Entry<String, List<String>>>>() {}.getType());
+        List<Map.Entry<String, List<String>>> parse = JsonMapper.parseJsonObject(jsonString, new TypeReference<List<Map.Entry<String, List<String>>>>() {}.getType());
         System.out.println(parse);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1588.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1588.java
index 05008e7ca..39ee127f6 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1588.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1500/Issue1588.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -14,7 +14,7 @@ public class Issue1588 {
         Date date = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").parse(dateString);
         JSONObject jsonObject = new JSONObject();
         jsonObject.put("test", date);
-        System.out.println(JSON.toJSONString(jsonObject, "iso8601"));
-        System.out.println(JSON.toJSONString(jsonObject, "yyyy-MM-dd'T'HH:mm:ssXXX"));
+        System.out.println(JsonMapper.toJsonString(jsonObject, "iso8601"));
+        System.out.println(JsonMapper.toJsonString(jsonObject, "yyyy-MM-dd'T'HH:mm:ssXXX"));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_field.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_field.java
index 41f32a097..e44b4fef8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_field.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_field.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.ArrayList;
@@ -13,19 +12,19 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1603_field {
     @Test
     public void test_emptySet() throws Exception {
-        Model_1 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_1.class);
+        Model_1 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_1.class);
         assertEquals(0, m.values.size());
     }
 
     @Test
     public void test_emptyList() throws Exception {
-        Model_2 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_2.class);
+        Model_2 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_2.class);
         assertEquals(0, m.values.size());
     }
 
     @Test
     public void test_unmodifier() throws Exception {
-        Model_3 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_3.class);
+        Model_3 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_3.class);
         assertEquals(0, m.values.size());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_field_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_field_private.java
index 25c54c7dc..7625e0ed0 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_field_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_field_private.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.ArrayList;
@@ -13,19 +12,19 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1603_field_private {
     @Test
     public void test_emptySet() throws Exception {
-        Model_1 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_1.class);
+        Model_1 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_1.class);
         assertEquals(0, m.values.size());
     }
 
     @Test
     public void test_emptyList() throws Exception {
-        Model_2 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_2.class);
+        Model_2 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_2.class);
         assertEquals(0, m.values.size());
     }
 
     @Test
     public void test_unmodifier() throws Exception {
-        Model_3 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_3.class);
+        Model_3 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_3.class);
         assertEquals(0, m.values.size());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_getter.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_getter.java
index efa7e0f16..74a17d641 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_getter.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_getter.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.ArrayList;
@@ -13,19 +12,19 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1603_getter {
     @Test
     public void test_emptySet() throws Exception {
-        Model_1 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_1.class);
+        Model_1 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_1.class);
         assertEquals(0, m.values.size());
     }
 
     @Test
     public void test_emptyList() throws Exception {
-        Model_2 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_2.class);
+        Model_2 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_2.class);
         assertEquals(0, m.values.size());
     }
 
     @Test
     public void test_unmodifier() throws Exception {
-        Model_3 m = JSON.parseObject("{\"values\":[\"a\"]}", Model_3.class);
+        Model_3 m = JsonMapper.parseJsonObject("{\"values\":[\"a\"]}", Model_3.class);
         assertEquals(0, m.values.size());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_map.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_map.java
index 4a82c7bd5..4106540d5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_map.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_map.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Collections;
@@ -13,13 +12,13 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1603_map {
     @Test
     public void test_emptyMap() throws Exception {
-        Model_1 m = JSON.parseObject("{\"values\":{\"a\":1001}}", Model_1.class);
+        Model_1 m = JsonMapper.parseJsonObject("{\"values\":{\"a\":1001}}", Model_1.class);
         assertEquals(0, m.values.size());
     }
 
     @Test
     public void test_unmodifiableMap() throws Exception {
-        Model_2 m = JSON.parseObject("{\"values\":{\"a\":1001}}", Model_2.class);
+        Model_2 m = JsonMapper.parseJsonObject("{\"values\":{\"a\":1001}}", Model_2.class);
         assertEquals(0, m.values.size());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_map_getter.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_map_getter.java
index 4a2e2f403..92962eaec 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_map_getter.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1603_map_getter.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.Collections;
@@ -13,13 +12,13 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1603_map_getter {
     @Test
     public void test_emptyMap() throws Exception {
-        Model_1 m = JSON.parseObject("{\"values\":{\"a\":1001}}", Model_1.class);
+        Model_1 m = JsonMapper.parseJsonObject("{\"values\":{\"a\":1001}}", Model_1.class);
         assertEquals(0, m.values.size());
     }
 
     @Test
     public void test_unmodifiableMap() throws Exception {
-        Model_2 m = JSON.parseObject("{\"values\":{\"a\":1001}}", Model_2.class);
+        Model_2 m = JsonMapper.parseJsonObject("{\"values\":{\"a\":1001}}", Model_2.class);
         assertEquals(0, m.values.size());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1611.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1611.java
index cff220a17..c27b51852 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1611.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1611.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONArray;
 import com.alibaba.fastjson2.JSONObject;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,7 +11,7 @@ public class Issue1611 {
     @Test
     public void test_for_issue() throws Exception {
         String pristineJson = "{\"data\":{\"lists\":[{\"Name\":\"Mark\"}]}}";
-        JSONArray list = JSON.parseObject(pristineJson).getJSONObject("data").getJSONArray("lists");
+        JSONArray list = JsonMapper.parseJsonObject(pristineJson).getJSONObject("data").getJSONArray("lists");
         assertEquals(1, list.size());
         for (int i = 0; i < list.size(); i++) {
             JSONObject sss = list.getJSONObject(i);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1627.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1627.java
index 983eb665e..7090fe1f5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1627.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1627.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertTrue;
@@ -11,7 +10,7 @@ public class Issue1627 {
     @Test
     public void test_for_issue() throws Exception {
         String a = "{\"101a0.test-b\":\"tt\"}";
-        Object o = JSON.parse(a);
+        Object o = JsonMapper.parseJson(a);
         String s = "101a0.test-b";
         assertTrue(JSONPath
                 .of("$." + escapeString(s))
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1628.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1628.java
index 2a12a779d..6a87f4333 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1628.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1628.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.filter.Filter;
 import com.alibaba.fastjson2.filter.SimplePropertyPreFilter;
 import org.junit.jupiter.api.Test;
@@ -16,7 +16,7 @@ public class Issue1628 {
         Map<String, Object> map = new HashMap<String, Object>();
         map.put("a", 1001);
         map.put("b", 2002);
-        byte[] bytes = JSON.toJSONBytes(map, new SimplePropertyPreFilter("a"));
+        byte[] bytes = JsonMapper.toJsonBytes(map, new SimplePropertyPreFilter("a"));
         assertEquals("{\"a\":1001}", new String(bytes));
     }
 
@@ -25,7 +25,7 @@ public class Issue1628 {
         Map<String, Object> map = new HashMap<String, Object>();
         map.put("a", 1001);
         map.put("b", 2002);
-        byte[] bytes = JSON.toJSONBytes(map, new Filter[] {new SimplePropertyPreFilter("a")});
+        byte[] bytes = JsonMapper.toJsonBytes(map, new Filter[] {new SimplePropertyPreFilter("a")});
         assertEquals("{\"a\":1001}", new String(bytes));
     }
 
@@ -34,7 +34,7 @@ public class Issue1628 {
         Map<String, Object> map = new HashMap<String, Object>();
         map.put("a", 1001);
         map.put("b", 2002);
-        byte[] bytes = JSON.toJSONBytes(map, new SimplePropertyPreFilter("a"));
+        byte[] bytes = JsonMapper.toJsonBytes(map, new SimplePropertyPreFilter("a"));
         assertEquals("{\"a\":1001}", new String(bytes));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1636.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1636.java
index eaf13d61e..e6fe25d31 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1636.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1636.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -11,13 +10,13 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1636 {
     @Test
     public void test_for_issue_1() throws Exception {
-        Item1 item = JSON.parseObject("{\"modelId\":1001}", Item1.class);
+        Item1 item = JsonMapper.parseJsonObject("{\"modelId\":1001}", Item1.class);
         assertEquals(1001, item.modelId);
     }
 
     @Test
     public void test_for_issue_2() throws Exception {
-        Item2 item = JSON.parseObject("{\"modelId\":1001}", Item2.class);
+        Item2 item = JsonMapper.parseJsonObject("{\"modelId\":1001}", Item2.class);
         assertEquals(1001, item.modelId);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1645.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1645.java
index e2a578fa4..cb55de8db 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1645.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1645.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.time.LocalDateTime;
@@ -9,7 +9,7 @@ public class Issue1645 {
     @Test
     public void test_for_issue() throws Exception {
         String test = "{\"name\":\"test\",\"testDateTime\":\"2017-12-08 14:55:16\"}";
-        JSON.toJSONString(JSON.parseObject(test).toJavaObject(TestDateClass.class));
+        JsonMapper.toJsonString(JsonMapper.parseJsonObject(test).toJavaObject(TestDateClass.class));
     }
 
     public static class TestDateClass{
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1649.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1649.java
index 7248c969e..9682bb18e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1649.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1649.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONType;
 import com.alibaba.fastjson2.JSONWriter.Feature;
 import org.junit.jupiter.api.Test;
@@ -11,7 +11,7 @@ public class Issue1649 {
     @Test
     public void test_for_issue() throws Exception {
         Apple apple = new Apple();
-        String json = JSON.toJSONString(apple);
+        String json = JsonMapper.toJsonString(apple);
         assertEquals("{\"color\":\"\",\"productCity\":\"\",\"size\":0}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1649_private.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1649_private.java
index 7d24ca865..b6f999aac 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1649_private.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1649_private.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONType;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,7 +11,7 @@ public class Issue1649_private {
     @Test
     public void test_for_issue() throws Exception {
         Apple apple = new Apple();
-        String json = JSON.toJSONString(apple);
+        String json = JsonMapper.toJsonString(apple);
         assertEquals("{\"color\":\"\",\"productCity\":\"\",\"size\":0}", json);
     }
 
@@ -53,11 +52,11 @@ public class Issue1649_private {
 
         @Override
         public String toString() {
-            return JSON.toJSONString(this);
+            return JsonMapper.toJsonString(this);
         }
 
         public static void main(String[] args) {
-            System.out.println(JSON.toJSONString(new Apple()));
+            System.out.println(JsonMapper.toJsonString(new Apple()));
         }
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1657.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1657.java
index 72878d186..3cc6923eb 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1657.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1657.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -11,7 +10,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1657 {
     @Test
     public void test_for_issue() throws Exception {
-        HashMap map = JSON.parseObject("\"\"", HashMap.class);
+        HashMap map = JsonMapper.parseJsonObject("\"\"", HashMap.class);
         assertEquals(0, map.size());
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1660.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1660.java
index 4953309af..7b04f0d6f 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1660.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1660.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.*;
@@ -16,7 +15,7 @@ public class Issue1660 {
         Model model = new Model();
         model.values.add(new Date(1513755213202L));
 
-        String json = JSON.toJSONString(model);
+        String json = JsonMapper.toJsonString(model);
         assertEquals("{\"values\":[\"2017-12-20\"]}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1679.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1679.java
index 3fdeac6a5..76d14a401 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1679.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue1679.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.Date;
@@ -15,7 +14,7 @@ public class Issue1679 {
     @Test
     public void test_for_issue() throws Exception {
         String json = "{\"create\":\"2018-01-10 08:30:00\"}";
-        User user = JSON.parseObject(json, User.class);
+        User user = JsonMapper.parseJsonObject(json, User.class);
 
         JSONWriter jsonWriter = JSONWriter.of();
         jsonWriter.getContext().setDateFormat("iso8601");
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue_for_gaorui.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue_for_gaorui.java
index 0e1cbec92..e82bb6540 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue_for_gaorui.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/Issue_for_gaorui.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import org.junit.jupiter.api.Test;
 
@@ -9,7 +9,7 @@ public class Issue_for_gaorui {
     public void test_for_issue() throws Exception {
         String json = "{\"@type\":\"java.util.HashMap\",\"COUPON\":[{\"@type\":\"com.alibaba.fastjson2.v1issues.issue_1600.Issue_for_gaorui.PromotionTermDetail\",\"activityId\":\"1584034\",\"choose\":true,\"couponId\":1251068987,\"couponType\":\"limitp\",\"match\":true,\"realPrice\":{\"amount\":0.6,\"currency\":\"USD\"}}],\"grayTrade\":\"true\"}";
 
-        JSON.parseObject(json, Object.class, JSONReader.Feature.SupportAutoType);
+        JsonMapper.parseJsonObject(json, Object.class, JSONReader.Feature.SupportAutoType);
     }
 
     public static class PromotionTermDetail {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/issue_1699/TestJson.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/issue_1699/TestJson.java
index 97bf711d5..9d4199338 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/issue_1699/TestJson.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1600/issue_1699/TestJson.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1600.issue_1699;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import org.junit.jupiter.api.Test;
 
@@ -15,7 +15,7 @@ public class TestJson {
 //        System.out.println(JSON.VERSION);
 
         String event1 = "{\"@type\":\"com.alibaba.fastjson2.v1issues.issue_1600.issue_1699.obj.RatingDetailBO\",\"amount\":285.600000,\"billId\":3945,\"bizId\":\"6000007==201712==USER_ID==2049884395&&CONTRACT_NO==\\\"no1513922344271\\\"\",\"bizTime\":\"2017-12-31 00:00:00\",\"bizType\":\"6000007\",\"currency\":\"CNY\",\"dealTime\":\"2017-12-23 14:11:03\",\"detailType\":\"CYCLE_CHARGING\",\"extendInfo\":{\"@type\":\"java.util.LinkedHashMap\",\"BUY_AMOUNT\":\"3\",\"P_BIZ_ID\":\"USER_ID==2049884395&&CONTRACT_NO==\\\"no1513922344271\\\"\",\"SETTLE_SIDE\":\"654321\",\"SETTLE_CYCLE_TYPE\":\"3\",\"AUCTION_PRICE\":\"119\",\"CALCULATE_RANGE\":\"STORE\",\"TOTAL_NUM\":\"1\",\"BILL_CYCLE\":\"201712\",\"IS_PRE_CHARGING\":\"false\",\"BRANCH_SHOP\":\"branchShop1\",\"CONTRACT_TYPE\":\"HEMA_CHARGING_PROD\",\"stepRateType\":\"3\",\"SOURCE_TYPE\":\"PURCHASE_ADJUST\",\"SETTLE_SIDE_NICK\":\"测试结算主体\",\"express_value\":\"USER_ID==2049884395&&CONTRACT_NO==\\\"no1513922344271\\\"\",\"BIZ_TIME\":\"2017-12-22 13:59:05\",\"TRADE_ID\":\"1513922344273\",\"QUANTITY\":\"3.000000\",\"MES_RECEIVE_TIME\":\"2017-12-22 13:59:05\",\"UN_TAX_UNIT_PRICE\":\"100.000000\",\"AUCTION_ID\":\"123\",\"AUCTION_NAME\":\"测试商品\",\"rate_value\":\"{\\\"extendInfo\\\":{},\\\"intervalValues\\\":[{\\\"max\\\":600.000000,\\\"min\\\":0.000000,\\\"rate\\\":0.600000},{\\\"max\\\":1000.000000,\\\"min\\\":600.000000,\\\"rate\\\":0.300000},{\\\"max\\\":999999999999.000000,\\\"min\\\":1000.000000,\\\"rate\\\":0.100000}]}\",\"CAT_ID\":\"16\",\"UNIT\":\"kilometer\",\"TERM_NAME\":\"盒马.合同返利.促销推广费\",\"USER_ID\":\"2049884395\",\"UNIT_PRICE\":\"119.000000\",\"tbRuleCode\":\"HM_SETTLE_CHARGING\",\"AMOUNT\":\"357.000000\",\"CAT_NAME\":\"水果\",\"EXTERNAL_NO\":\"HM==1513922344273\",\"CHANNEL\":\"online\",\"is_default_rate\":\"false\",\"CURRENCY\":\"CNY\",\"rate_rule_id\":\"300000531\",\"OTHER_USER_NICK\":\"甲方\",\"RATE_TYPE\":\"14\",\"ITEM_NAME\":\"盒马.促销推广费\",\"rate_rule_inst_id\":\"1009129180821\",\"TAX_RATE\":\"0.190000\",\"ITEM_CODE\":\"BILL_HM_6000007\",\"CONTRACT_SIDE\":\"12345\",\"UNTAX_AMOUNT\":\"300.000000\",\"CONTRACT_VERSION\":\"V001\",\"CONTRACT_NO\":\"no1513922344271\",\"P_TRADE_ID\":\"1513922344273\"},\"gmtCreate\":\"2017-12-23 14:11:03\",\"gmtModified\":\"2017-12-23 14:11:03\",\"id\":6235300020395,\"indexNum\":0,\"innerId\":6300120395,\"innerTable\":\"SETTLE_DATA\",\"isJoin\":\"FALSE\",\"itemId\":90000000007031,\"mesId\":3235,\"mesReceiveTime\":\"2017-12-22 13:59:05\",\"outBizId\":\"USER_ID==2049884395&&CONTRACT_NO==\\\"no1513922344271\\\"\",\"pTradeId\":3235,\"priority\":0,\"proration\":0.6,\"quantity\":476.000000,\"rateDefineId\":40000443,\"rateParams\":{\"@type\":\"java.util.LinkedHashMap\"},\"status\":\"SUCCESS\",\"tradeId\":3761,\"userId\":2049884395,\"userNick\":\"乙方\",\"version\":1}";
-        Serializable obj = JSON.parseObject(event1, Serializable.class, JSONReader.Feature.SupportAutoType);
+        Serializable obj = JsonMapper.parseJsonObject(event1, Serializable.class, JSONReader.Feature.SupportAutoType);
         System.out.println(obj);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1723.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1723.java
index 8ce69a9c1..d47d8a38e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1723.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1723.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -10,19 +9,19 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1723 {
     @Test
     public void test_for_issue() throws Exception {
-        User user = JSON.parseObject("{\"age\":\"0.9390308260917664\"}", User.class);
+        User user = JsonMapper.parseJsonObject("{\"age\":\"0.9390308260917664\"}", User.class);
         assertEquals(0.9390308260917664F, user.age);
     }
 
     @Test
     public void test_for_issue_1() throws Exception {
-        User user = JSON.parseObject("{\"age\":\"8.200000000000001\"}", User.class);
+        User user = JsonMapper.parseJsonObject("{\"age\":\"8.200000000000001\"}", User.class);
         assertEquals(8.200000000000001F, user.age);
     }
 
     @Test
     public void test_for_issue_2() throws Exception {
-        User user = JSON.parseObject("[\"8.200000000000001\"]", User.class, JSONReader.Feature.SupportArrayToBean);
+        User user = JsonMapper.parseJsonObject("[\"8.200000000000001\"]", User.class, JSONReader.Feature.SupportArrayToBean);
         assertEquals(8.200000000000001F, user.age);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1725.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1725.java
index c340997f9..730357333 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1725.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1725.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -15,7 +14,7 @@ public class Issue1725 {
         Map<String, Object> map= new HashMap<String, Object>();
         map.put("enumField", 0);
 
-        AbstractBean bean = JSON.parseObject(JSON.toJSONString(map), ConcreteBean.class);
+        AbstractBean bean = JsonMapper.parseJsonObject(JsonMapper.toJsonString(map), ConcreteBean.class);
         assertEquals(FieldEnum.A, bean.enumField);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1727.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1727.java
index 11e12afa3..dd4adc4c8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1727.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1727.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.Date;
@@ -11,8 +10,8 @@ public class Issue1727 {
     @Test
     public void test_for_issue() throws Exception {
         String jsonString = "{\"gmtCreate\":\"20180131214157805-0800\"}";
-        JSON.parseObject(jsonString, Model.class); //正常解析
-        JSON.parseObject(jsonString).toJavaObject(Model.class);
+        JsonMapper.parseJsonObject(jsonString, Model.class); //正常解析
+        JsonMapper.parseJsonObject(jsonString).toJavaObject(Model.class);
     }
 
     public static class Model {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1739.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1739.java
index 0ebc06c16..d0907d365 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1739.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1739.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -13,7 +13,7 @@ public class Issue1739 {
         M0 model = new M0();
         model.data = new JSONObject();
 
-        String json = JSON.toJSONString(model);
+        String json = JsonMapper.toJsonString(model);
         assertEquals("{\"data\":{}}", json);
     }
 
@@ -22,7 +22,7 @@ public class Issue1739 {
         M1 model = new M1();
         model.data = new JSONObject();
 
-        String json = JSON.toJSONString(model);
+        String json = JsonMapper.toJsonString(model);
         assertEquals("{}", json);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1763.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1763.java
index 52dcb5665..f314df6bc 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1763.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1763.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.lang.reflect.Method;
@@ -19,7 +19,7 @@ public class Issue1763 {
         Method method = ProcurementOrderInteractiveServiceForCloud.class.getMethod("queryOrderMateriel", Map.class);
         Type type = method.getGenericReturnType();
 
-        BaseResult<InteractiveOrderMaterielQueryResult> baseResult = JSON.parseObject(s, type);
+        BaseResult<InteractiveOrderMaterielQueryResult> baseResult = JsonMapper.parseJsonObject(s, type);
         InteractiveOrderMaterielQueryResult result = baseResult.getResult();
 
         assertEquals(7, result.getModelList().size());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764.java
index 59ac10c2f..1add2b4ea 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONField;
 import com.alibaba.fastjson2.annotation.JSONType;
@@ -15,7 +15,7 @@ public class Issue1764 {
         Model model = new Model();
         model.value = 9007199254741992L;
 
-        String str = JSON.toJSONString(model);
+        String str = JsonMapper.toJsonString(model);
         assertEquals("{\"value\":\"9007199254741992\"}", str);
     }
 
@@ -24,7 +24,7 @@ public class Issue1764 {
         Model1 model = new Model1();
         model.value = 9007199254741992L;
 
-        String str = JSON.toJSONString(model);
+        String str = JsonMapper.toJsonString(model);
         assertEquals("{\"value\":\"9007199254741992\"}", str);
     }
 
@@ -33,7 +33,7 @@ public class Issue1764 {
         Model2 model = new Model2();
         model.value = 9007199254741992L;
 
-        String str = JSON.toJSONString(model);
+        String str = JsonMapper.toJsonString(model);
         assertEquals("{\"value\":\"9007199254741992\"}", str);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean.java
index 995507095..7d719857e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONType;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -12,23 +11,23 @@ public class Issue1764_bean {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals("{\"value\":\"9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254741992L)));
 
         assertEquals("{\"value\":\"9007199254741990\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254741990L)));
 
         assertEquals("{\"value\":100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(100L)));
 
         assertEquals("{\"value\":\"-9007199254741990\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254741990L)));
 
         assertEquals("{\"value\":-9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254740990L)));
 
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger.java
index aa841904d..610930492 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.math.BigInteger;
@@ -13,27 +12,27 @@ public class Issue1764_bean_biginteger {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals("{\"value\":\"9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254741992L), JSONWriter.Feature.BrowserCompatible));
 
         assertEquals("{\"value\":\"-9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254741992L), JSONWriter.Feature.BrowserCompatible));
 
         assertEquals("{\"value\":9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254740990L), JSONWriter.Feature.BrowserCompatible));
 
         assertEquals("{\"value\":-9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254740990L), JSONWriter.Feature.BrowserCompatible));
 
         assertEquals("{\"value\":100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(100), JSONWriter.Feature.BrowserCompatible));
 
         assertEquals("{\"value\":-100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-100), JSONWriter.Feature.BrowserCompatible));
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger_field.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger_field.java
index b1365fc92..35efe2058 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger_field.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger_field.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.math.BigInteger;
@@ -14,27 +13,27 @@ public class Issue1764_bean_biginteger_field {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals("{\"value\":\"9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254741992L)));
 
         assertEquals("{\"value\":\"-9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254741992L)));
 
         assertEquals("{\"value\":9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254740990L)));
 
         assertEquals("{\"value\":-9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254740990L)));
 
         assertEquals("{\"value\":100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(100)));
 
         assertEquals("{\"value\":-100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-100)));
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger_type.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger_type.java
index 0cf14bc0d..799d01039 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger_type.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1764_bean_biginteger_type.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.JSONType;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.math.BigInteger;
@@ -14,27 +13,27 @@ public class Issue1764_bean_biginteger_type {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals("{\"value\":\"9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254741992L)));
 
         assertEquals("{\"value\":\"-9007199254741992\"}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254741992L)));
 
         assertEquals("{\"value\":9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(9007199254740990L)));
 
         assertEquals("{\"value\":-9007199254740990}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-9007199254740990L)));
 
         assertEquals("{\"value\":100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(100)));
 
         assertEquals("{\"value\":-100}"
-                , JSON.toJSONString(
+                , JsonMapper.toJsonString(
                         new Model(-100)));
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1766.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1766.java
index 0a0a2592d..25eac846d 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1766.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1766.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
 
@@ -13,13 +13,13 @@ public class Issue1766 {
     public void test_for_issue() throws Exception {
 // succ
         String json = "{\"name\":\"张三\"\n, \"birthday\":\"2017-01-01 01:01:01\"}";
-        User user = JSON.parseObject(json, User.class);
+        User user = JsonMapper.parseJsonObject(json, User.class);
         assertEquals("张三", user.getName());
         assertNotNull(user.getBirthday());
 
         // failed
         json = "{\"name\":\"张三\", \"birthday\":\"2017-01-01 01:01:02\"\n}";
-        user = JSON.parseObject(json, User.class);// will exception
+        user = JsonMapper.parseJsonObject(json, User.class);// will exception
         assertEquals("张三", user.getName());
         assertNotNull(user.getBirthday());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1772.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1772.java
index 68797e445..bdccaa2ab 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1772.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1700/Issue1772.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import org.junit.jupiter.api.Test;
 
@@ -11,7 +11,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue1772 {
     @Test
     public void test_0() throws Exception {
-        Date date = JSON.parseObject("\"-14189155200000\"", Date.class);
+        Date date = JsonMapper.parseJsonObject("\"-14189155200000\"", Date.class);
         assertEquals(-14189155200000L, date.getTime());
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1800/Issue1879.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1800/Issue1879.java
index 075d485b9..8c120ac85 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1800/Issue1879.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1800/Issue1879.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_1800;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
@@ -20,7 +20,7 @@ public class Issue1879 {
         String json = "{\n" +
                 "   \"ids\" : \"1,2,3\"\n" +
                 "}";
-        M1 m = JSON.parseObject(json, M1.class);
+        M1 m = JsonMapper.parseJsonObject(json, M1.class);
     }
 
     @Test
@@ -28,7 +28,7 @@ public class Issue1879 {
         String json = "{\n" +
                 "   \"ids\" : \"1,2,3\"\n" +
                 "}";
-        M2 m = JSON.parseObject(json, M2.class);
+        M2 m = JsonMapper.parseJsonObject(json, M2.class);
         assertNotNull(m);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_2700/Issue2791.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_2700/Issue2791.java
index a2b1d3620..69a1e93ec 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_2700/Issue2791.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_2700/Issue2791.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_2700;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.JSONPath;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -11,7 +10,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue2791 {
     @Test
     public void test_for_issue() throws Exception {
-        JSONObject jsonObject = JSON.parseObject("{\"dependencies\":[{\"values\":[{\"name\":\"Demo\"}]}]}");
+        JSONObject jsonObject = JsonMapper.parseJsonObject("{\"dependencies\":[{\"values\":[{\"name\":\"Demo\"}]}]}");
         JSONPath.of("$.dependencies.values[?(@.name=='Demo')]")
                 .remove(jsonObject);
         assertEquals("{\"dependencies\":[{\"values\":[]}]}", jsonObject.toString());
@@ -26,7 +25,7 @@ public class Issue2791 {
 
     @Test
     public void test_for_issue2() throws Exception {
-        JSONObject jsonObject = JSON.parseObject("{\"values\":[{\"name\":\"Demo\"}]}");
+        JSONObject jsonObject = JsonMapper.parseJsonObject("{\"values\":[{\"name\":\"Demo\"}]}");
         JSONPath.of("$.values[?(@.name=='Demo')]")
                 .remove(jsonObject);
         assertEquals("{\"values\":[]}", jsonObject.toString());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266.java
index d28545dbe..2895ef4a7 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -14,12 +14,12 @@ public class Issue3266 {
         vo.type = Color.Black;
 
         assertEquals("1003"
-                , JSON.toJSONString(vo.type));
+                , JsonMapper.toJsonString(vo.type));
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"type\":1003}", str);
 
-        VO vo2 = JSON.parseObject(str, VO.class);
+        VO vo2 = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(vo.type, vo2.type);
     }
 
@@ -29,12 +29,12 @@ public class Issue3266 {
         vo.type = Color.Black;
 
         assertEquals("1003"
-                , JSON.toJSONString(vo.type));
+                , JsonMapper.toJsonString(vo.type));
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"type\":1003}", str);
 
-        V1 vo2 = JSON.parseObject(str, V1.class);
+        V1 vo2 = JsonMapper.parseJsonObject(str, V1.class);
         assertEquals(vo.type, vo2.type);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266_mixedin.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266_mixedin.java
index 73d60e565..e4e7a515c 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266_mixedin.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266_mixedin.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -10,35 +10,35 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue3266_mixedin {
     @Test
     public void test_for_issue() throws Exception {
-        JSON.mixIn(Color.class, ColorMixedIn.class);
+        JsonMapper.addMixIn(Color.class, ColorMixedIn.class);
 
         VO vo = new VO();
         vo.type = Color.Black;
 
         assertEquals("1003"
-                , JSON.toJSONString(vo.type));
+                , JsonMapper.toJsonString(vo.type));
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"type\":1003}", str);
 
-        VO vo2 = JSON.parseObject(str, VO.class);
+        VO vo2 = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(vo.type, vo2.type);
     }
 
     @Test
     public void test_for_issue_method() throws Exception {
-        JSON.mixIn(Color.class, ColorMixedIn.class);
+        JsonMapper.addMixIn(Color.class, ColorMixedIn.class);
 
         V1 vo = new V1();
         vo.type = Color.Black;
 
         assertEquals("1003"
-                , JSON.toJSONString(vo.type));
+                , JsonMapper.toJsonString(vo.type));
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"type\":1003}", str);
 
-        V1 vo2 = JSON.parseObject(str, V1.class);
+        V1 vo2 = JsonMapper.parseJsonObject(str, V1.class);
         assertEquals(vo.type, vo2.type);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266_str.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266_str.java
index ffd409760..49ec55111 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266_str.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3200/Issue3266_str.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3200;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import com.alibaba.fastjson2.annotation.JSONField;
 import org.junit.jupiter.api.Test;
@@ -14,12 +14,12 @@ public class Issue3266_str {
         vo.type = Color.Black;
 
         assertEquals("\"黑色\""
-                , JSON.toJSONString(vo.type));
+                , JsonMapper.toJsonString(vo.type));
 
-        String str = JSON.toJSONString(vo);
+        String str = JsonMapper.toJsonString(vo);
         assertEquals("{\"type\":\"黑色\"}", str);
 
-        VO vo2 = JSON.parseObject(str, VO.class);
+        VO vo2 = JsonMapper.parseJsonObject(str, VO.class);
         assertEquals(vo.type, vo2.type);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3313.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3313.java
index 918c7bb64..9c0030dac 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3313.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3313.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import lombok.Data;
 import org.junit.jupiter.api.Test;
 
@@ -17,7 +16,7 @@ public class Issue3313 {
     @Test
     public void test_for_issue() throws Exception {
         String jsonStr = "{\"NAME\":\"nanqi\",\"age\":18}";
-        Model model = JSON.parseObject(jsonStr, Model.class, JSONReader.Feature.SupportSmartMatch);
+        Model model = JsonMapper.parseJsonObject(jsonStr, Model.class, JSONReader.Feature.SupportSmartMatch);
         assertNotNull(model.getAGe());
         assertNotNull(model.getName());
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3326.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3326.java
index 835d54e00..3340541c0 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3326.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3326.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.TypeReference;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.math.BigDecimal;
@@ -13,7 +12,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue3326 {
     @Test
     public void test_for_issue() throws Exception {
-        HashMap<String, Number> map = JSON.parseObject("{\"id\":10.0}"
+        HashMap<String, Number> map = JsonMapper.parseJsonObject("{\"id\":10.0}"
                 , new TypeReference<HashMap<String, Number>>() {
                     }.getType()
                 );
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3334.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3334.java
index b982571e8..3642d14c7 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3334.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3334.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -10,43 +9,43 @@ public class Issue3334 {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals(0,
-                JSON.parseObject("{\"id\":false}", VO.class).id);
+                JsonMapper.parseJsonObject("{\"id\":false}", VO.class).id);
 
         assertEquals(1,
-                JSON.parseObject("{\"id\":true}", VO.class).id);
+                JsonMapper.parseJsonObject("{\"id\":true}", VO.class).id);
 
 
         assertEquals(0,
-                JSON.parseObject("{\"id64\":false}", VO.class).id64);
+                JsonMapper.parseJsonObject("{\"id64\":false}", VO.class).id64);
 
         assertEquals(1,
-                JSON.parseObject("{\"id64\":true}", VO.class).id64);
+                JsonMapper.parseJsonObject("{\"id64\":true}", VO.class).id64);
 
         assertEquals(0,
-                JSON.parseObject("{\"id16\":false}", VO.class).id16);
+                JsonMapper.parseJsonObject("{\"id16\":false}", VO.class).id16);
 
         assertEquals(1,
-                JSON.parseObject("{\"id16\":true}", VO.class).id16);
+                JsonMapper.parseJsonObject("{\"id16\":true}", VO.class).id16);
 
 
         assertEquals(0,
-                JSON.parseObject("{\"id8\":false}", VO.class).id8);
+                JsonMapper.parseJsonObject("{\"id8\":false}", VO.class).id8);
 
         assertEquals(1,
-                JSON.parseObject("{\"id8\":true}", VO.class).id8);
+                JsonMapper.parseJsonObject("{\"id8\":true}", VO.class).id8);
 
 
         assertEquals(0F,
-                JSON.parseObject("{\"floatValue\":false}", VO.class).floatValue);
+                JsonMapper.parseJsonObject("{\"floatValue\":false}", VO.class).floatValue);
 
         assertEquals(1F,
-                JSON.parseObject("{\"floatValue\":true}", VO.class).floatValue);
+                JsonMapper.parseJsonObject("{\"floatValue\":true}", VO.class).floatValue);
 
         assertEquals(0D,
-                JSON.parseObject("{\"doubleValue\":false}", VO.class).doubleValue);
+                JsonMapper.parseJsonObject("{\"doubleValue\":false}", VO.class).doubleValue);
 
         assertEquals(1D,
-                JSON.parseObject("{\"doubleValue\":true}", VO.class).doubleValue);
+                JsonMapper.parseJsonObject("{\"doubleValue\":true}", VO.class).doubleValue);
     }
 
     public static class VO {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3336.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3336.java
index 347db9caf..2282e40a5 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3336.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3336.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -10,15 +9,15 @@ public class Issue3336 {
     @Test
     public void test_for_issue() throws Exception {
         String s = "{\"schema\":{\"$ref\":\"#/definitions/URLJumpConfig\"}}";
-        assertEquals(s, JSON.parseObject(s)
+        assertEquals(s, JsonMapper.parseJsonObject(s)
                 .toJSONString());
 
         String s1 = "{\"schema\":{\"ref\":\"#/definitions/URLJumpConfig\"}}";
-        assertEquals(s1, JSON.parseObject(s1)
+        assertEquals(s1, JsonMapper.parseJsonObject(s1)
                 .toJSONString());
 
         String s2 = "{\"schema\":{\"$ref\":\"#/definitions/URLJumpConfig\"}}";
-        assertEquals(s2, JSON.parseObject(s2)
+        assertEquals(s2, JsonMapper.parseJsonObject(s2)
                 .toJSONString());
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3338.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3338.java
index d47950151..17f17a7d9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3338.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3338.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
 import com.alibaba.fastjson2.JSONObject;
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -23,7 +22,7 @@ public class Issue3338 {
         map.put("nanqi", "因为相信，所以看见。");
         model.setMap(map);
 
-        String jsonString = JSON.toJSONString(model);
+        String jsonString = JsonMapper.toJsonString(model);
         assertTrue(jsonString.contains("因为相信，所以看见。"));
 
         Model modelBack = JSONObject.parseObject(jsonString, Model.class);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3347.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3347.java
index 98440da9d..859d6fe88 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3347.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3347.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.util.HashMap;
@@ -19,7 +18,7 @@ public class Issue3347 {
     public void test_for_issue() throws Exception {
         Map<Integer, String> map = new HashMap<Integer, String>();
         map.put(1, "hello");
-        String mapJSONString = JSON.toJSONString(map);
+        String mapJSONString = JsonMapper.toJsonString(map);
         Map mapValues = JSONObject.parseObject(mapJSONString, Map.class);
         Object mapKey = mapValues.keySet().iterator().next();
         assertTrue(mapKey instanceof String);
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3375.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3375.java
index f5fbd5234..dbded3607 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3375.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3375.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.util.ArrayList;
@@ -28,8 +27,8 @@ public class Issue3375 {
         models.add(map2);
 
         for (Map<String, String> model : models) {
-            String modelStr = JSON.toJSONString(model);
-            Model modelObj = JSON.parseObject(modelStr, Model.class);
+            String modelStr = JsonMapper.toJsonString(model);
+            Model modelObj = JsonMapper.parseJsonObject(modelStr, Model.class);
             assertTrue(modelObj.getName().contains("nanqi"));
         }
     }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3397.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3397.java
index dd4bcbbd5..683bdeeef 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3397.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/Issue3397.java
@@ -1,9 +1,8 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONObject;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.time.LocalDateTime;
@@ -17,9 +16,9 @@ public class Issue3397 {
     @Test
     public void test_for_issue() throws Exception {
         String text = "{\"date\":\"2020-08-16 16:35:18.188\"}";
-        VO vo = JSON.parseObject(text, VO.class);
+        VO vo = JsonMapper.parseJsonObject(text, VO.class);
 
-        JSONObject json = (JSONObject) JSON.toJSON(vo);
+        JSONObject json = (JSONObject) JsonMapper.toJson(vo);
 
         Date date = json.getDate("date");
 //        assertEquals("Sun Aug 16 16:35:18 CST 2020", date.toString());
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/IssueForJSONFieldMatch.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/IssueForJSONFieldMatch.java
index f55bb9658..d1f39cb86 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/IssueForJSONFieldMatch.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3300/IssueForJSONFieldMatch.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_3300;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONField;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -11,13 +10,13 @@ public class IssueForJSONFieldMatch {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals(123
-                , JSON.parseObject("{\"user_id\":123}", VO.class)
+                , JsonMapper.parseJsonObject("{\"user_id\":123}", VO.class)
                         .userId);
         assertEquals(123
-                , JSON.parseObject("{\"userId\":123}", VO.class)
+                , JsonMapper.parseJsonObject("{\"userId\":123}", VO.class)
                         .userId);
         assertEquals(123
-                , JSON.parseObject("{\"user-id\":123}", VO.class)
+                , JsonMapper.parseJsonObject("{\"user-id\":123}", VO.class)
                         .userId);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3516.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3516.java
index 884131eff..490d6ad4a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3516.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3516.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertTrue;
@@ -8,6 +8,6 @@ import static org.junit.jupiter.api.Assertions.assertTrue;
 public class Issue3516 {
     @Test
     public void test_for_issue() throws Exception {
-        assertTrue(JSON.isValid("{}"));
+        assertTrue(JsonMapper.isValid("{}"));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3521.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3521.java
index 549f51908..ff77122b8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3521.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3521.java
@@ -1,7 +1,5 @@
 package com.alibaba.fastjson2.v1issues.issue_3500;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertFalse;
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3539.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3539.java
index 1439c5f25..46fa69d0b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3539.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3539.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.time.Instant;
@@ -11,33 +11,33 @@ public class Issue3539 {
     @Test
     public void test_for_issue() throws Exception {
         String str = "{\"date\":{\"nano\":140000000,\"epochSecond\":1605106869}}";
-        Bean bean = JSON.parseObject(str, Bean.class);
+        Bean bean = JsonMapper.parseJsonObject(str, Bean.class);
         assertNotNull(bean.date);
-        JSON.toJSONString(bean);
+        JsonMapper.toJsonString(bean);
 
-        JSON.parseObject(str)
+        JsonMapper.parseJsonObject(str)
                 .toJavaObject(Bean.class);
     }
 
     @Test
     public void test_for_issue_joda() throws Exception {
         String str = "{\"date\":{\"epochSecond\":1605106869}}";
-        JodaBean bean = JSON.parseObject(str, JodaBean.class);
+        JodaBean bean = JsonMapper.parseJsonObject(str, JodaBean.class);
         assertNotNull(bean.date);
-        JSON.toJSONString(bean);
+        JsonMapper.toJsonString(bean);
 
-        JSON.parseObject(str)
+        JsonMapper.parseJsonObject(str)
                 .toJavaObject(JodaBean.class);
     }
 
     @Test
     public void test_for_issue_joda2() throws Exception {
         String str = "{\"date\":{\"millis\":1605364826724}}";
-        JodaBean bean = JSON.parseObject(str, JodaBean.class);
+        JodaBean bean = JsonMapper.parseJsonObject(str, JodaBean.class);
         assertNotNull(bean.date);
-        JSON.toJSONString(bean);
+        JsonMapper.toJsonString(bean);
 
-        JSON.parseObject(str)
+        JsonMapper.parseJsonObject(str)
                 .toJavaObject(JodaBean.class);
     }
 
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3544.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3544.java
index 3472f8a07..cffc26b3b 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3544.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3544.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3500;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import lombok.Getter;
 import lombok.Setter;
 import org.junit.jupiter.api.Test;
@@ -15,11 +14,11 @@ public class Issue3544 {
 
     @Test
     public void test_errorType() {
-        assertNull(JSON.toJavaObject(
-                JSON.parseObject("{\"result\":\"\"}"), TestVO.class).result);
+        assertNull(JsonMapper.convertToJavaObject(
+                JsonMapper.parseJsonObject("{\"result\":\"\"}"), TestVO.class).result);
 
-        assertNull(JSON.toJavaObject(
-                JSON.parseObject("{\"result\":\"null\"}"), TestVO.class).result);
+        assertNull(JsonMapper.convertToJavaObject(
+                JsonMapper.parseJsonObject("{\"result\":\"null\"}"), TestVO.class).result);
     }
 
     @Getter
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3571.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3571.java
index 40ed73bcb..e0956bc5e 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3571.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3571.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3500;
 
-import com.alibaba.fastjson2.JSON;
-import junit.framework.TestCase;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -14,7 +13,7 @@ public class Issue3571 {
         bean.id2 = 102;
         bean.id3 = 103;
 
-        assertEquals("{\"id1\":101,\"id2\":102,\"id3\":103}", JSON.toJSON(bean).toString());
+        assertEquals("{\"id1\":101,\"id2\":102,\"id3\":103}", JsonMapper.toJson(bean).toString());
     }
 
     @Test
@@ -24,7 +23,7 @@ public class Issue3571 {
         bean.id2 = 102;
         bean.id3 = 103;
 
-        assertEquals("{\"id1\":101,\"id2\":102,\"id3\":103}", JSON.toJSON(bean).toString());
+        assertEquals("{\"id1\":101,\"id2\":102,\"id3\":103}", JsonMapper.toJson(bean).toString());
     }
 
     public static class Bean1 {
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3579.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3579.java
index 98a92abe5..c24b614f9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3579.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3500/Issue3579.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_3500;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import junit.framework.TestCase;
 import org.junit.jupiter.api.Test;
 
 import java.math.BigDecimal;
@@ -13,11 +12,11 @@ public class Issue3579 {
     @Test
     public void test_for_issue() throws Exception {
         assertEquals("1",
-                JSON.toJSONString(new BigDecimal("1"))
+                JsonMapper.toJsonString(new BigDecimal("1"))
         );
 
         assertEquals("1",
-                JSON.toJSONString(new BigDecimal("1"), JSONWriter.Feature.WriteClassName)
+                JsonMapper.toJsonString(new BigDecimal("1"), JSONWriter.Feature.WriteClassName)
         );
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3600/Issue3671.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3600/Issue3671.java
index 574629d94..af3827068 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3600/Issue3671.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3600/Issue3671.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import java.nio.charset.StandardCharsets;
@@ -24,9 +24,9 @@ public class Issue3671 {
                 "}]\n";
         byte[] utf8 = json.getBytes(StandardCharsets.UTF_8);
 
-        assertTrue(JSON.isValid(json));
-        assertTrue(JSON.isValid(utf8));
-        assertTrue(JSON.isValid(utf8, 0, utf8.length, StandardCharsets.UTF_8));
-        assertTrue(JSON.isValid(utf8, 0, utf8.length, StandardCharsets.US_ASCII));
+        assertTrue(JsonMapper.isValid(json));
+        assertTrue(JsonMapper.isValid(utf8));
+        assertTrue(JsonMapper.isValid(utf8, 0, utf8.length, StandardCharsets.UTF_8));
+        assertTrue(JsonMapper.isValid(utf8, 0, utf8.length, StandardCharsets.US_ASCII));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3600/Issue3689.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3600/Issue3689.java
index bf416aa4e..d4d5ea8fe 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3600/Issue3689.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_3600/Issue3689.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_3600;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONException;
 import org.junit.jupiter.api.Test;
 
@@ -11,70 +11,70 @@ public class Issue3689 {
     @Test
     public void test_without_type_0_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("dfdfdf");
+            JsonMapper.parseJsonArray("dfdfdf");
         });
     }
 
     @Test
     public void test_without_type_1_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("/dfdfdf");
+            JsonMapper.parseJsonArray("/dfdfdf");
         });
     }
 
     @Test
     public void test_without_type_2_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("//dfdfdf");
+            JsonMapper.parseJsonArray("//dfdfdf");
         });
     }
 
     @Test
     public void test_without_type_3_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("///dfdfdf");
+            JsonMapper.parseJsonArray("///dfdfdf");
         });
     }
 
     @Test
     public void test_without_type_4_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("////dfdfdf");
+            JsonMapper.parseJsonArray("////dfdfdf");
         });
     }
 
     @Test
     public void test_without_type_5_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("/////dfdfdf");
+            JsonMapper.parseJsonArray("/////dfdfdf");
         });
     }
 
     @Test
     public void test_without_type_6_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("//////dfdfdf");
+            JsonMapper.parseJsonArray("//////dfdfdf");
         });
     }
 
     @Test
     public void test_with_type_0_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("dfdfdf", String.class);
+            JsonMapper.parseJsonArray("dfdfdf", String.class);
         });
     }
 
     @Test
     public void test_with_type_1_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("/dfdfdf", String.class);
+            JsonMapper.parseJsonArray("/dfdfdf", String.class);
         });
     }
 
     @Test
     public void test_with_type_2_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("//dfdfdf", String.class);
+            JsonMapper.parseJsonArray("//dfdfdf", String.class);
         });
 
     }
@@ -82,7 +82,7 @@ public class Issue3689 {
     @Test
     public void test_with_type_3_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("///dfdfdf", String.class);
+            JsonMapper.parseJsonArray("///dfdfdf", String.class);
         });
 
     }
@@ -90,7 +90,7 @@ public class Issue3689 {
     @Test
     public void test_with_type_4_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("////dfdfdf", String.class);
+            JsonMapper.parseJsonArray("////dfdfdf", String.class);
         });
 
     }
@@ -98,7 +98,7 @@ public class Issue3689 {
     @Test
     public void test_with_type_5_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("/////dfdfdf", String.class);
+            JsonMapper.parseJsonArray("/////dfdfdf", String.class);
         });
 
     }
@@ -106,13 +106,13 @@ public class Issue3689 {
     @Test
     public void test_with_type_6_meaningles_char() {
         assertThrows(JSONException.class, () -> {
-            JSON.parseArray("//////dfdfdf", String.class);
+            JsonMapper.parseJsonArray("//////dfdfdf", String.class);
         });
     }
 
     @Test
     public void test_for_issue() {
-        JSON.parseArray("[\"////dfdfdf\"]"); //不会抛异常
-        JSON.parse("[\"dfdfdf\"]");//不会抛异常
+        JsonMapper.parseJsonArray("[\"////dfdfdf\"]"); //不会抛异常
+        JsonMapper.parseJson("[\"dfdfdf\"]");//不会抛异常
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_4000/Issue4050.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_4000/Issue4050.java
index 26d7e8fae..d193f2c6a 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_4000/Issue4050.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_4000/Issue4050.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.v1issues.issue_4000;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertFalse;
@@ -10,6 +10,6 @@ public class Issue4050 {
     public void test_validate() {
         String str = "{\"file\":\"d:\\abc.txt\"}";
         assertFalse(
-                JSON.isValid(str));
+                JsonMapper.isValid(str));
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson2_demo/MappingDemo.java b/core/src/test/java/com/alibaba/fastjson2_demo/MappingDemo.java
index eb820c490..5b4fbd012 100644
--- a/core/src/test/java/com/alibaba/fastjson2_demo/MappingDemo.java
+++ b/core/src/test/java/com/alibaba/fastjson2_demo/MappingDemo.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2_demo;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONWriter;
 import org.junit.jupiter.api.Test;
@@ -15,8 +15,8 @@ public class MappingDemo {
         Product product = new Product();
         product.id = 1;
         product.name = "DataWorks";
-        System.out.println(JSON.toJSONString(product));
-        System.out.println(JSON.toJSONString(product, JSONWriter.Feature.BeanToArray));
+        System.out.println(JsonMapper.toJsonString(product));
+        System.out.println(JsonMapper.toJsonString(product, JSONWriter.Feature.BeanToArray));
     }
 
     @Test
@@ -36,8 +36,8 @@ public class MappingDemo {
         productList.add(new Product(3, "EMR"));
         productList.add(new Product(4, "Holo"));
 
-        System.out.println(JSON.toJSONString(productList));
-        System.out.println(JSON.toJSONString(productList, JSONWriter.Feature.BeanToArray));
+        System.out.println(JsonMapper.toJsonString(productList));
+        System.out.println(JsonMapper.toJsonString(productList, JSONWriter.Feature.BeanToArray));
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/CartResponsePerf.java b/core/src/test/java/com/alibaba/fastjson_perf/CartResponsePerf.java
index c4382513e..965c2c012 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/CartResponsePerf.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/CartResponsePerf.java
@@ -1,11 +1,11 @@
 package com.alibaba.fastjson_perf;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2_vo.cart.CartResponse;
 
 public class CartResponsePerf {
     public void test_perf() throws Exception {
         String str = null;
-        CartResponse response = JSON.parseObject(str, CartResponse.class);
+        CartResponse response = JsonMapper.parseJsonObject(str, CartResponse.class);
     }
 }
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/DaoyanPerf.java b/core/src/test/java/com/alibaba/fastjson_perf/DaoyanPerf.java
index e5fac10cd..405d69091 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/DaoyanPerf.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/DaoyanPerf.java
@@ -230,9 +230,9 @@ public class DaoyanPerf {
             JSONB.parseObject(jsonbBytes, type);
         }
         {
-            jsonBytes = JSON.toJSONBytes(lists);
+            jsonBytes = JsonMapper.toJsonBytes(lists);
             Type type = new TypeReference<List<CartItemDO>>(){}.getType();
-            JSON.parseObject(jsonBytes, type);
+            JsonMapper.parseJsonObject(jsonBytes, type);
         }
         {
             jdkBytes = serializeByJdk(lists);
@@ -331,7 +331,7 @@ public class DaoyanPerf {
             long start = System.currentTimeMillis();
 
             for (int j = 0; j < LOOP_COUNT; j++) {
-                copyOfWrittenBuffer = JSON.toJSONBytes(lists);
+                copyOfWrittenBuffer = JsonMapper.toJsonBytes(lists);
             }
 
             System.out.println("json : millis " + (System.currentTimeMillis() - start) + ", len " + copyOfWrittenBuffer.length);
@@ -347,7 +347,7 @@ public class DaoyanPerf {
             long start = System.currentTimeMillis();
 
             for (int j = 0; j < LOOP_COUNT; j++) {
-                JSON.parseObject(jsonBytes, type);
+                JsonMapper.parseJsonObject(jsonBytes, type);
             }
 
             System.out.println("json-parse : millis " + (System.currentTimeMillis() - start) + ", len " + jsonBytes.length);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/DoubleTest.java b/core/src/test/java/com/alibaba/fastjson_perf/DoubleTest.java
index 5a68b3bb6..f391e819d 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/DoubleTest.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/DoubleTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2_vo.DoubleField10;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -32,7 +32,7 @@ public class DoubleTest {
             long start = System.currentTimeMillis();
 
             for (int j = 0; j < 1000 * 1000 * 1; ++j) {
-                JSON.toJSONString(bean);
+                JsonMapper.toJsonString(bean);
             }
 
             long millis = System.currentTimeMillis() - start;
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/EishayTest.java b/core/src/test/java/com/alibaba/fastjson_perf/EishayTest.java
index e12f8e5fd..50b674ddc 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/EishayTest.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/EishayTest.java
@@ -5,6 +5,7 @@ import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.eishay.vo.*;
 import com.alibaba.fastjson2.reader.*;
 import com.alibaba.fastjson2.util.JSONBDump;
@@ -77,7 +78,7 @@ public class EishayTest {
             long start = System.currentTimeMillis();
 
             for (int j = 0; j < 1000 * 1000; ++j) {
-                String str = com.alibaba.fastjson2.JSON.toJSONString(mc);
+                String str = JsonMapper.toJsonString(mc);
                 str.length();
             }
 
@@ -100,7 +101,7 @@ public class EishayTest {
             long start = System.currentTimeMillis();
 
             for (int j = 0; j < 1000 * 1000; ++j) {
-                byte[] str = com.alibaba.fastjson2.JSON.toJSONBytes(mc);
+                byte[] str = JsonMapper.toJsonBytes(mc);
                 len = str.length;
             }
 
@@ -118,13 +119,13 @@ public class EishayTest {
     public void test_read_utf8_default() {
         mc = JSONReader.of(str)
                 .read(MediaContent.class);
-        byte[] utf8Bytes = com.alibaba.fastjson2.JSON.toJSONBytes(mc);
+        byte[] utf8Bytes = JsonMapper.toJsonBytes(mc);
 
         for (int i = 0; i < 10; ++i) {
             long start = System.currentTimeMillis();
 
             for (int j = 0; j < 1000 * 1000; ++j) {
-                com.alibaba.fastjson2.JSON.parseObject(utf8Bytes, MediaContent.class);
+                JsonMapper.parseJsonObject(utf8Bytes, MediaContent.class);
             }
 
             long millis = System.currentTimeMillis() - start;
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/FloatArrayPerf.java b/core/src/test/java/com/alibaba/fastjson_perf/FloatArrayPerf.java
index 2f590177f..d6175cf97 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/FloatArrayPerf.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/FloatArrayPerf.java
@@ -1,8 +1,7 @@
 package com.alibaba.fastjson_perf;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
-import com.alibaba.fastjson2_vo.Float10;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import org.junit.jupiter.api.Test;
 
@@ -25,7 +24,7 @@ public class FloatArrayPerf {
             long start = System.currentTimeMillis();
 
             for (int j = 0; j < 1000 * 1000 * 1; ++j) {
-                JSON.toJSONString(array);
+                JsonMapper.toJsonString(array);
             }
 
             long millis = System.currentTimeMillis() - start;
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/FloatTest.java b/core/src/test/java/com/alibaba/fastjson_perf/FloatTest.java
index d28a88e0d..9496c2284 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/FloatTest.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/FloatTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2_vo.Float10;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -32,7 +32,7 @@ public class FloatTest {
             long start = System.currentTimeMillis();
 
             for (int j = 0; j < 1000 * 1000 * 1; ++j) {
-                JSON.toJSONString(date1);
+                JsonMapper.toJsonString(date1);
             }
 
             long millis = System.currentTimeMillis() - start;
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/HSFPerf.java b/core/src/test/java/com/alibaba/fastjson_perf/HSFPerf.java
index c335c4e53..86a0c99a6 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/HSFPerf.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/HSFPerf.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -15,7 +15,7 @@ public class HSFPerf {
 
         JSONB.parseObject(bytes, VeryComplexDO.class);
 
-        System.out.println(JSON.toJSONString(vo));
+        System.out.println(JsonMapper.toJsonString(vo));
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/HSFPerf2.java b/core/src/test/java/com/alibaba/fastjson_perf/HSFPerf2.java
index d823bbb93..5b5a298f7 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/HSFPerf2.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/HSFPerf2.java
@@ -1,7 +1,7 @@
 package com.alibaba.fastjson_perf;
 
 import com.alibaba.fastjson.JSONObject;
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -26,7 +26,7 @@ public class HSFPerf2 {
 
         JSONB.parseObject(bytes, Result.class);
 
-        System.out.println(JSON.toJSONString(result));
+        System.out.println(JsonMapper.toJsonString(result));
     }
 
     @Test
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/HomePagePerf.java b/core/src/test/java/com/alibaba/fastjson_perf/HomePagePerf.java
index 4c7f89867..7f7c47b16 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/HomePagePerf.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/HomePagePerf.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2_vo.homepage.GetHomePageResponse;
 import org.apache.commons.io.IOUtils;
@@ -19,12 +19,12 @@ public class HomePagePerf {
 
     @Test
     public void test_homepage() {
-        GetHomePageResponse resp = JSON.parseObject(str, GetHomePageResponse.class);
-        String str2 = JSON.toJSONString(resp);
-        String str2_pretty = JSON.toJSONString(resp);
-        String str3 = JSON.toJSONString(resp, JSONWriter.Feature.BeanToArray);
-        byte[] bytes = JSON.toJSONBytes(resp);
-        byte[] bytes2 = JSON.toJSONBytes(resp, JSONWriter.Feature.BeanToArray);
+        GetHomePageResponse resp = JsonMapper.parseJsonObject(str, GetHomePageResponse.class);
+        String str2 = JsonMapper.toJsonString(resp);
+        String str2_pretty = JsonMapper.toJsonString(resp);
+        String str3 = JsonMapper.toJsonString(resp, JSONWriter.Feature.BeanToArray);
+        byte[] bytes = JsonMapper.toJsonBytes(resp);
+        byte[] bytes2 = JsonMapper.toJsonBytes(resp, JSONWriter.Feature.BeanToArray);
         System.out.println(str2);
 
     }
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseString.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseString.java
index c8439b14f..ee7e7f4e8 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseString.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseString.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
 import com.alibaba.fastjson_perf.Int2Test;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -25,7 +25,7 @@ public class EishayParseString {
         try {
             InputStream is = Int2Test.class.getClassLoader().getResourceAsStream("data/eishay_compact.json");
             str = IOUtils.toString(is, "UTF-8");
-            com.alibaba.fastjson2.JSON.parseObject(str, MediaContent.class);
+            JsonMapper.parseJsonObject(str, MediaContent.class);
         } catch (Throwable ex) {
             ex.printStackTrace();
         }
@@ -38,7 +38,7 @@ public class EishayParseString {
 
     @Benchmark
     public void fastjson2() {
-        com.alibaba.fastjson2.JSON.parseObject(str, MediaContent.class);
+        JsonMapper.parseJsonObject(str, MediaContent.class);
     }
 
     @Benchmark
@@ -63,7 +63,7 @@ public class EishayParseString {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            com.alibaba.fastjson2.JSON.parseObject(str, MediaContent.class);
+            JsonMapper.parseJsonObject(str, MediaContent.class);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("millis : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseStringPretty.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseStringPretty.java
index f8c2b6c1a..3490242fb 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseStringPretty.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseStringPretty.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.eishay.vo.*;
 import com.alibaba.fastjson_perf.Int2Test;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -37,7 +37,7 @@ public class EishayParseStringPretty {
 
     @Benchmark
     public void fastjson2() {
-        JSON.parseObject(str, MediaContent.class);
+        JsonMapper.parseJsonObject(str, MediaContent.class);
     }
 
     @Benchmark
@@ -55,7 +55,7 @@ public class EishayParseStringPretty {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(str, MediaContent.class);
+            JsonMapper.parseJsonObject(str, MediaContent.class);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("millis : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeString.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeString.java
index 0b85464bb..d32010be4 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeString.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeString.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
 import com.alibaba.fastjson_perf.Int2Test;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -26,7 +26,7 @@ public class EishayParseTreeString {
         try {
             InputStream is = Int2Test.class.getClassLoader().getResourceAsStream("data/eishay_compact.json");
             str = IOUtils.toString(is, "UTF-8");
-            JSON.parseObject(str, MediaContent.class);
+            JsonMapper.parseJsonObject(str, MediaContent.class);
         } catch (Throwable ex) {
             ex.printStackTrace();
         }
@@ -39,7 +39,7 @@ public class EishayParseTreeString {
 
     @Benchmark
     public void fastjson2() {
-        JSON.parseObject(str);
+        JsonMapper.parseJsonObject(str);
     }
 
     @Benchmark
@@ -64,7 +64,7 @@ public class EishayParseTreeString {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(str);
+            JsonMapper.parseJsonObject(str);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("millis : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeStringPretty.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeStringPretty.java
index 97feb88e6..e0d8f042b 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeStringPretty.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeStringPretty.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
 import com.alibaba.fastjson_perf.Int2Test;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -26,7 +26,7 @@ public class EishayParseTreeStringPretty {
         try {
             InputStream is = Int2Test.class.getClassLoader().getResourceAsStream("data/eishay.json");
             str = IOUtils.toString(is, "UTF-8");
-            JSON.parseObject(str, MediaContent.class);
+            JsonMapper.parseJsonObject(str, MediaContent.class);
         } catch (Throwable ex) {
             ex.printStackTrace();
         }
@@ -39,7 +39,7 @@ public class EishayParseTreeStringPretty {
 
     @Benchmark
     public void fastjson2() {
-        JSON.parseObject(str);
+        JsonMapper.parseJsonObject(str);
     }
 
     @Benchmark
@@ -64,7 +64,7 @@ public class EishayParseTreeStringPretty {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(str);
+            JsonMapper.parseJsonObject(str);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("millis : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeUTF8Bytes.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeUTF8Bytes.java
index 88556b804..bc2bfbd14 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeUTF8Bytes.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeUTF8Bytes.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson_perf.Int2Test;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import org.apache.commons.io.IOUtils;
@@ -38,7 +38,7 @@ public class EishayParseTreeUTF8Bytes {
 
     @Benchmark
     public void fastjson2() {
-        JSON.parseObject(utf8Bytes);
+        JsonMapper.parseJsonObject(utf8Bytes);
     }
 
     @Benchmark
@@ -56,7 +56,7 @@ public class EishayParseTreeUTF8Bytes {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(utf8Bytes);
+            JsonMapper.parseJsonObject(utf8Bytes);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("millis : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeUTF8BytesPretty.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeUTF8BytesPretty.java
index 943dfaa04..b391126af 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeUTF8BytesPretty.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseTreeUTF8BytesPretty.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson_perf.Int2Test;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import org.apache.commons.io.IOUtils;
@@ -38,7 +38,7 @@ public class EishayParseTreeUTF8BytesPretty {
 
     @Benchmark
     public void fastjson2() {
-        JSON.parseObject(utf8Bytes);
+        JsonMapper.parseJsonObject(utf8Bytes);
     }
 
     @Benchmark
@@ -56,7 +56,7 @@ public class EishayParseTreeUTF8BytesPretty {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(utf8Bytes);
+            JsonMapper.parseJsonObject(utf8Bytes);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("millis : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseUTF8Bytes.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseUTF8Bytes.java
index 4b28161af..aa5b884bd 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseUTF8Bytes.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseUTF8Bytes.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
 import com.alibaba.fastjson_perf.Int2Test;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -38,7 +38,7 @@ public class EishayParseUTF8Bytes {
 
     @Benchmark
     public void fastjson2() {
-        JSON.parseObject(utf8Bytes, MediaContent.class);
+        JsonMapper.parseJsonObject(utf8Bytes, MediaContent.class);
     }
 
     @Benchmark
@@ -56,7 +56,7 @@ public class EishayParseUTF8Bytes {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(utf8Bytes, MediaContent.class);
+            JsonMapper.parseJsonObject(utf8Bytes, MediaContent.class);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("EishayParseUTF8Bytes : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseUTF8BytesPretty.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseUTF8BytesPretty.java
index f546bf1ce..f5fa5b3b2 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseUTF8BytesPretty.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayParseUTF8BytesPretty.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
 import com.alibaba.fastjson_perf.Int2Test;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -38,7 +38,7 @@ public class EishayParseUTF8BytesPretty {
 
     @Benchmark
     public void fastjson2() {
-        JSON.parseObject(utf8Bytes, MediaContent.class);
+        JsonMapper.parseJsonObject(utf8Bytes, MediaContent.class);
     }
 
     @Benchmark
@@ -56,7 +56,7 @@ public class EishayParseUTF8BytesPretty {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(utf8Bytes, MediaContent.class);
+            JsonMapper.parseJsonObject(utf8Bytes, MediaContent.class);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("millis : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteBinary.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteBinary.java
index 31fc27258..a484554da 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteBinary.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteBinary.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
@@ -36,7 +36,7 @@ public class EishayWriteBinary {
 
     @Benchmark
     public void fastjson2UTF8Bytes() {
-        JSON.toJSONBytes(mc);
+        JsonMapper.toJsonBytes(mc);
     }
 
     @Benchmark
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteString.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteString.java
index 61d4f888e..506575ded 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteString.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteString.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
 import com.alibaba.fastjson_perf.Int2Test;
@@ -38,7 +38,7 @@ public class EishayWriteString {
 
     @Benchmark
     public void fastjson2() {
-        JSON.toJSONString(mc);
+        JsonMapper.toJsonString(mc);
     }
 
     @Benchmark
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteUTF8Bytes.java b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteUTF8Bytes.java
index 6385cb8fe..cd95e38d4 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteUTF8Bytes.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/eishay/EishayWriteUTF8Bytes.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.eishay;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
 import com.alibaba.fastjson_perf.Int2Test;
@@ -40,7 +40,7 @@ public class EishayWriteUTF8Bytes {
 
     @Benchmark
     public void fastjson2() {
-        JSON.toJSONBytes(mc);
+        JsonMapper.toJsonBytes(mc);
     }
 
     @Test
@@ -53,7 +53,7 @@ public class EishayWriteUTF8Bytes {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.toJSONBytes(mc);
+            JsonMapper.toJsonBytes(mc);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("millis : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/primitves/String20Test.java b/core/src/test/java/com/alibaba/fastjson_perf/primitves/String20Test.java
index c56a3a593..d38f69a4c 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/primitves/String20Test.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/primitves/String20Test.java
@@ -1,7 +1,6 @@
 package com.alibaba.fastjson_perf.primitves;
 
-import com.alibaba.fastjson2.JSON;
-import com.alibaba.fastjson2.eishay.vo.MediaContent;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2_vo.String20;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import org.apache.commons.io.IOUtils;
@@ -36,7 +35,7 @@ public class String20Test {
 
     @Benchmark
     public void fastjson2() {
-        com.alibaba.fastjson2.JSON.parseObject(str, String20.class);
+        JsonMapper.parseJsonObject(str, String20.class);
     }
 
     @Benchmark
@@ -54,7 +53,7 @@ public class String20Test {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(str, String20.class);
+            JsonMapper.parseJsonObject(str, String20.class);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println("String20Test : " + millis);
diff --git a/core/src/test/java/com/alibaba/fastjson_perf/primitves/StringField20Test.java b/core/src/test/java/com/alibaba/fastjson_perf/primitves/StringField20Test.java
index b121e7f91..6611797a3 100644
--- a/core/src/test/java/com/alibaba/fastjson_perf/primitves/StringField20Test.java
+++ b/core/src/test/java/com/alibaba/fastjson_perf/primitves/StringField20Test.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson_perf.primitves;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2_vo.StringField20;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import org.apache.commons.io.IOUtils;
@@ -35,7 +35,7 @@ public class StringField20Test {
 
     @Benchmark
     public void fastjson2() {
-        JSON.parseObject(str, StringField20.class);
+        JsonMapper.parseJsonObject(str, StringField20.class);
     }
 
     @Benchmark
@@ -53,7 +53,7 @@ public class StringField20Test {
     public static void fastjson2_perf() {
         long start = System.currentTimeMillis();
         for (int i = 0; i < 1000 * 1000; ++i) {
-            JSON.parseObject(str, StringField20.class);
+            JsonMapper.parseJsonObject(str, StringField20.class);
         }
         long millis = System.currentTimeMillis() - start;
         System.out.println(StringField20.class.getSimpleName() + " : " + millis);
diff --git a/extension/src/main/java/com/alibaba/fastjson2/support/retrofit/Retrofit2ConverterFactory.java b/extension/src/main/java/com/alibaba/fastjson2/support/retrofit/Retrofit2ConverterFactory.java
index fd356be13..49f7314b3 100644
--- a/extension/src/main/java/com/alibaba/fastjson2/support/retrofit/Retrofit2ConverterFactory.java
+++ b/extension/src/main/java/com/alibaba/fastjson2/support/retrofit/Retrofit2ConverterFactory.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.retrofit;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import okhttp3.MediaType;
 import okhttp3.RequestBody;
@@ -79,7 +79,7 @@ public class Retrofit2ConverterFactory extends Converter.Factory {
         @Override
         public T convert(ResponseBody value) throws IOException {
             try {
-                return JSON.parseObject(value.bytes(), type, fastJsonConfig.getReaderFeatures());
+                return JsonMapper.parseJsonObject(value.bytes(), type, fastJsonConfig.getReaderFeatures());
             } catch (Exception e) {
                 throw new IOException("JSON parse error: " + e.getMessage(), e);
             } finally {
@@ -95,7 +95,7 @@ public class Retrofit2ConverterFactory extends Converter.Factory {
         @Override
         public RequestBody convert(T value) throws IOException {
             try {
-                byte[] content = JSON.toJSONBytes(value,
+                byte[] content = JsonMapper.toJsonBytes(value,
                         fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
                 return RequestBody.create(MEDIA_TYPE, content);
             } catch (Exception e) {
diff --git a/extension/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/FastJsonRedisSerializer.java b/extension/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/FastJsonRedisSerializer.java
index 7fbce5964..bb4f69b5b 100644
--- a/extension/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/FastJsonRedisSerializer.java
+++ b/extension/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/FastJsonRedisSerializer.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.spring.data.redis;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import org.springframework.data.redis.serializer.RedisSerializer;
 import org.springframework.data.redis.serializer.SerializationException;
@@ -36,7 +36,7 @@ public class FastJsonRedisSerializer<T> implements RedisSerializer<T> {
             return new byte[0];
         }
         try {
-            return JSON.toJSONBytes(t, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
+            return JsonMapper.toJsonBytes(t, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
 
         } catch (Exception ex) {
             throw new SerializationException("Could not serialize: " + ex.getMessage(), ex);
@@ -49,7 +49,7 @@ public class FastJsonRedisSerializer<T> implements RedisSerializer<T> {
             return null;
         }
         try {
-            return (T) JSON.parseObject(bytes, type, fastJsonConfig.getReaderFeatures());
+            return (T) JsonMapper.parseJsonObject(bytes, type, fastJsonConfig.getReaderFeatures());
 
         } catch (Exception ex) {
             throw new SerializationException("Could not deserialize: " + ex.getMessage(), ex);
diff --git a/extension/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/GenericFastJsonRedisSerializer.java b/extension/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/GenericFastJsonRedisSerializer.java
index 4b343dfd6..80368e1ac 100644
--- a/extension/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/GenericFastJsonRedisSerializer.java
+++ b/extension/src/main/java/com/alibaba/fastjson2/support/spring/data/redis/GenericFastJsonRedisSerializer.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.spring.data.redis;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
@@ -30,7 +30,7 @@ public class GenericFastJsonRedisSerializer implements RedisSerializer<Object> {
             return new byte[0];
         }
         try {
-            return JSON.toJSONBytes(object, fastJsonConfig.getWriterFeatures());
+            return JsonMapper.toJsonBytes(object, fastJsonConfig.getWriterFeatures());
         } catch (Exception ex) {
             throw new SerializationException("Could not serialize: " + ex.getMessage(), ex);
         }
@@ -42,7 +42,7 @@ public class GenericFastJsonRedisSerializer implements RedisSerializer<Object> {
             return null;
         }
         try {
-            return JSON.parseObject(bytes, Object.class, fastJsonConfig.getReaderFeatures());
+            return JsonMapper.parseJsonObject(bytes, Object.class, fastJsonConfig.getReaderFeatures());
         } catch (Exception ex) {
             throw new SerializationException("Could not deserialize: " + ex.getMessage(), ex);
         }
diff --git a/extension/src/main/java/com/alibaba/fastjson2/support/spring/http/converter/FastJsonHttpMessageConverter.java b/extension/src/main/java/com/alibaba/fastjson2/support/spring/http/converter/FastJsonHttpMessageConverter.java
index a6bb40961..395d4b9f8 100644
--- a/extension/src/main/java/com/alibaba/fastjson2/support/spring/http/converter/FastJsonHttpMessageConverter.java
+++ b/extension/src/main/java/com/alibaba/fastjson2/support/spring/http/converter/FastJsonHttpMessageConverter.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.spring.http.converter;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONException;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import org.springframework.core.ResolvableType;
@@ -111,7 +111,7 @@ public class FastJsonHttpMessageConverter extends AbstractHttpMessageConverter<O
             }
             byte[] bytes = baos.toByteArray();
 
-            return JSON.parseObject(bytes, type, fastJsonConfig.getReaderFeatures());
+            return JsonMapper.parseJsonObject(bytes, type, fastJsonConfig.getReaderFeatures());
         } catch (JSONException ex) {
             throw new HttpMessageNotReadableException("JSON parse error: " + ex.getMessage(), ex, inputMessage);
         } catch (IOException ex) {
@@ -126,7 +126,7 @@ public class FastJsonHttpMessageConverter extends AbstractHttpMessageConverter<O
 
             HttpHeaders headers = outputMessage.getHeaders();
 
-            int len = JSON.writeTo(baos, object, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
+            int len = JsonMapper.writeToOutputStream(baos, object, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
 
             if (headers.getContentLength() < 0 && fastJsonConfig.isWriteContentLength()) {
 
diff --git a/extension/src/main/java/com/alibaba/fastjson2/support/spring/messaging/converter/MappingFastJsonMessageConverter.java b/extension/src/main/java/com/alibaba/fastjson2/support/spring/messaging/converter/MappingFastJsonMessageConverter.java
index f69f86b64..6f85d4edf 100644
--- a/extension/src/main/java/com/alibaba/fastjson2/support/spring/messaging/converter/MappingFastJsonMessageConverter.java
+++ b/extension/src/main/java/com/alibaba/fastjson2/support/spring/messaging/converter/MappingFastJsonMessageConverter.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.spring.messaging.converter;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import org.springframework.messaging.Message;
 import org.springframework.messaging.MessageHeaders;
@@ -63,9 +63,9 @@ public class MappingFastJsonMessageConverter extends AbstractMessageConverter {
         Object payload = message.getPayload();
         Object obj = null;
         if (payload instanceof byte[]) {
-            obj = JSON.parseObject((byte[]) payload, targetClass, fastJsonConfig.getReaderFeatures());
+            obj = JsonMapper.parseJsonObject((byte[]) payload, targetClass, fastJsonConfig.getReaderFeatures());
         } else if (payload instanceof String) {
-            obj = JSON.parseObject((String) payload, targetClass, fastJsonConfig.getReaderFeatures());
+            obj = JsonMapper.parseJsonObject((String) payload, targetClass, fastJsonConfig.getReaderFeatures());
         }
 
         return obj;
@@ -76,16 +76,16 @@ public class MappingFastJsonMessageConverter extends AbstractMessageConverter {
         // encode payload to json string or byte[]
         Object obj;
         if (byte[].class == getSerializedPayloadClass()) {
-            if (payload instanceof String && JSON.isValid((String) payload)) {
+            if (payload instanceof String && JsonMapper.isValid((String) payload)) {
                 obj = ((String) payload).getBytes(fastJsonConfig.getCharset());
             } else {
-                obj = JSON.toJSONBytes(payload, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
+                obj = JsonMapper.toJsonBytes(payload, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
             }
         } else {
-            if (payload instanceof String && JSON.isValid((String) payload)) {
+            if (payload instanceof String && JsonMapper.isValid((String) payload)) {
                 obj = payload;
             } else {
-                obj = JSON.toJSONString(payload, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
+                obj = JsonMapper.toJsonString(payload, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
             }
         }
 
diff --git a/extension/src/main/java/com/alibaba/fastjson2/support/spring/web/view/FastJsonJsonView.java b/extension/src/main/java/com/alibaba/fastjson2/support/spring/web/view/FastJsonJsonView.java
index a011dee9b..a85fad4b3 100644
--- a/extension/src/main/java/com/alibaba/fastjson2/support/spring/web/view/FastJsonJsonView.java
+++ b/extension/src/main/java/com/alibaba/fastjson2/support/spring/web/view/FastJsonJsonView.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.support.spring.web.view;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import org.springframework.http.MediaType;
 import org.springframework.util.CollectionUtils;
@@ -100,7 +100,7 @@ public class FastJsonJsonView extends AbstractView {
 
         ByteArrayOutputStream outnew = new ByteArrayOutputStream();
 
-        int len = JSON.writeTo(outnew, value, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
+        int len = JsonMapper.writeToOutputStream(outnew, value, fastJsonConfig.getWriterFilters(), fastJsonConfig.getWriterFeatures());
 
         if (fastJsonConfig.isWriteContentLength()) {
             // Write content length (determined via byte array).
diff --git a/extension/src/test/java/com/alibaba/fastjson2/retrofit/Retrofit2ConverterFactoryTest.java b/extension/src/test/java/com/alibaba/fastjson2/retrofit/Retrofit2ConverterFactoryTest.java
index 337f486d2..7082604cc 100644
--- a/extension/src/test/java/com/alibaba/fastjson2/retrofit/Retrofit2ConverterFactoryTest.java
+++ b/extension/src/test/java/com/alibaba/fastjson2/retrofit/Retrofit2ConverterFactoryTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.retrofit;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import com.alibaba.fastjson2.support.retrofit.Retrofit2ConverterFactory;
 import okhttp3.RequestBody;
@@ -23,7 +23,7 @@ public class Retrofit2ConverterFactoryTest {
         f.responseBodyConverter(Model.class, null, null);
 
         final Model model = new Model().setId(1).setName("test");
-        final String json = JSON.toJSONString(model);
+        final String json = JsonMapper.toJsonString(model);
         final ResponseBody body = new RealResponseBody("application/json; charset=UTF-8",
                 json.length(), new Buffer().writeUtf8(json));
 
@@ -37,7 +37,7 @@ public class Retrofit2ConverterFactoryTest {
                 .responseBodyConverter(Model.class, null, null)
                 .convert(body);
 
-        Assert.assertEquals(JSON.toJSONString(mode2), json);
+        Assert.assertEquals(JsonMapper.toJsonString(mode2), json);
 
         Assert.assertThrows(NullPointerException.class, () -> Retrofit2ConverterFactory.create()
                 .responseBodyConverter(null, null, null)
diff --git a/extension/src/test/java/com/alibaba/fastjson2/spring/MappingFastJsonMessageConverterTest.java b/extension/src/test/java/com/alibaba/fastjson2/spring/MappingFastJsonMessageConverterTest.java
index f1aa0c20b..d7cfa1244 100644
--- a/extension/src/test/java/com/alibaba/fastjson2/spring/MappingFastJsonMessageConverterTest.java
+++ b/extension/src/test/java/com/alibaba/fastjson2/spring/MappingFastJsonMessageConverterTest.java
@@ -1,6 +1,6 @@
 package com.alibaba.fastjson2.spring;
 
-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.support.config.FastJsonConfig;
 import com.alibaba.fastjson2.support.spring.messaging.converter.MappingFastJsonMessageConverter;
 import org.junit.jupiter.api.Test;
@@ -24,7 +24,7 @@ public class MappingFastJsonMessageConverterTest {
         VO p = new VO();
         p.setId(1);
 
-        String pstr = JSON.toJSONString(p);
+        String pstr = JsonMapper.toJsonString(p);
 
         System.out.println(pstr);
 
diff --git a/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSON.java b/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSON.java
index 7a28d61a8..e1f8797a5 100644
--- a/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSON.java
+++ b/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSON.java
@@ -9,6 +9,7 @@ import com.alibaba.fastjson.util.IOUtils;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.filter.PropertyFilter;
 import com.alibaba.fastjson2.filter.PropertyPreFilter;
 import com.alibaba.fastjson2.filter.ValueFilter;
@@ -31,7 +32,7 @@ import java.util.TimeZone;
 import java.util.concurrent.atomic.AtomicReferenceFieldUpdater;
 
 public class JSON {
-    public static final String VERSION = com.alibaba.fastjson2.JSON.VERSION;
+    public static final String VERSION = JsonMapper.VERSION;
 
     static class Cache {
         volatile char[] chars;
@@ -443,11 +444,11 @@ public class JSON {
     }
 
     public static boolean isValid(String str) {
-        return com.alibaba.fastjson2.JSON.isValid(str);
+        return JsonMapper.isValid(str);
     }
 
     public static boolean isValidArray(String str) {
-        return com.alibaba.fastjson2.JSON.isValidArray(str);
+        return JsonMapper.isValidArray(str);
     }
 
     public static <T> T toJavaObject(JSON json, Class<T> clazz) {
@@ -473,6 +474,6 @@ public class JSON {
     }
 
     public static List<Object> parseArray(String text, Type[] types) {
-        return com.alibaba.fastjson2.JSON.parseArray(text, types);
+        return JsonMapper.parseJsonArray(text, types);
     }
 }
diff --git a/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSONArray.java b/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSONArray.java
index f7b8345e3..3a6b4a10f 100644
--- a/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSONArray.java
+++ b/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSONArray.java
@@ -3,6 +3,7 @@ package com.alibaba.fastjson;
 import com.alibaba.fastjson2.JSONException;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.JSONReader;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.reader.ObjectReader;
 import com.alibaba.fastjson2.reader.ObjectReaderProvider;
 
@@ -164,7 +165,7 @@ public class JSONArray extends JSON implements List {
             return (String) value;
         }
 
-        return com.alibaba.fastjson2.JSON.toJSONString(value);
+        return JsonMapper.toJsonString(value);
     }
 
     public JSONArray getJSONArray(int index) {
@@ -236,6 +237,6 @@ public class JSONArray extends JSON implements List {
     }
 
     public <T> T toJavaObject(Class<T> clazz) {
-        return com.alibaba.fastjson2.JSON.toJavaObject(this, clazz);
+        return JsonMapper.convertToJavaObject(this, clazz);
     }
 }
diff --git a/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSONObject.java b/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSONObject.java
index 23838fad7..747e0d909 100755
--- a/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSONObject.java
+++ b/fastjson1-compatible/src/main/java/com/alibaba/fastjson/JSONObject.java
@@ -22,6 +22,7 @@ import com.alibaba.fastjson.util.TypeUtils;
 import com.alibaba.fastjson2.JSONException;
 import com.alibaba.fastjson2.JSONFactory;
 import com.alibaba.fastjson2.JSONReader;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.reader.ObjectReader;
 import com.alibaba.fastjson2.reader.ObjectReaderProvider;
 
@@ -621,8 +622,8 @@ public class JSONObject extends JSON implements Map<String, Object>, Cloneable,
         if (type instanceof Class) {
             return (T) JSONFactory.getDefaultObjectReaderProvider().getObjectReader(type).createInstance(this);
         }
-        String str = com.alibaba.fastjson2.JSON.toJSONString(this);
-        return (T) com.alibaba.fastjson2.JSON.parseObject(str, type);
+        String str = JsonMapper.toJsonString(this);
+        return (T) JsonMapper.parseJsonObject(str, type);
     }
 
     public <T> T toJavaObject(Class<T> clazz) {
@@ -656,12 +657,12 @@ public class JSONObject extends JSON implements Map<String, Object>, Cloneable,
     }
 
     public String toJSONString() {
-        return com.alibaba.fastjson2.JSON.toJSONString(this);
+        return JsonMapper.toJsonString(this);
     }
 
     @Override
     public String toString() {
-        return com.alibaba.fastjson2.JSON.toJSONString(this);
+        return JsonMapper.toJsonString(this);
     }
 
     public String toString(SerializerFeature... features) {
diff --git a/fastjson1-compatible/src/test/java/com/alibaba/fastjson/issue_3200/Issue3266_mixedin.java b/fastjson1-compatible/src/test/java/com/alibaba/fastjson/issue_3200/Issue3266_mixedin.java
index a94f61216..46dd98b2a 100644
--- a/fastjson1-compatible/src/test/java/com/alibaba/fastjson/issue_3200/Issue3266_mixedin.java
+++ b/fastjson1-compatible/src/test/java/com/alibaba/fastjson/issue_3200/Issue3266_mixedin.java
@@ -3,6 +3,7 @@ package com.alibaba.fastjson.issue_3200;
 import com.alibaba.fastjson.JSON;
 import com.alibaba.fastjson.annotation.JSONCreator;
 import com.alibaba.fastjson.annotation.JSONField;
+import com.alibaba.fastjson2.JsonMapper;
 import org.junit.jupiter.api.Test;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
@@ -10,7 +11,7 @@ import static org.junit.jupiter.api.Assertions.assertEquals;
 public class Issue3266_mixedin {
     @Test
     public void test_for_issue() throws Exception {
-        com.alibaba.fastjson2.JSON.mixIn(Color.class, ColorMixedIn.class);
+        JsonMapper.addMixIn(Color.class, ColorMixedIn.class);
 
         VO vo = new VO();
         vo.type = Color.Black;
diff --git a/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_1200/Issue1233.java b/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_1200/Issue1233.java
index 5c2f140fb..434c38e6a 100644
--- a/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_1200/Issue1233.java
+++ b/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_1200/Issue1233.java
@@ -3,6 +3,7 @@ package com.alibaba.json.bvt.issue_1200;
 import com.alibaba.fastjson.JSON;
 import com.alibaba.fastjson.JSONObject;
 import com.alibaba.fastjson.annotation.JSONType;
+import com.alibaba.fastjson2.JsonMapper;
 import junit.framework.TestCase;
 
 import java.util.List;
@@ -14,8 +15,8 @@ public class Issue1233 extends TestCase {
     public void test_for_issue() throws Exception {
         JSONObject jsonObject = JSON.parseObject("{\"type\":\"floorV2\",\"templateId\":\"x123\"}");
 
-        com.alibaba.fastjson2.JSON.mixIn(Area.class, AreaMixIn.class);
-        com.alibaba.fastjson2.JSON.mixIn(FloorV2.class, FloorV2MixIn.class);
+        JsonMapper.addMixIn(Area.class, AreaMixIn.class);
+        JsonMapper.addMixIn(FloorV2.class, FloorV2MixIn.class);
 
         FloorV2 floorV2 = (FloorV2) jsonObject.toJavaObject(Area.class);
         assertNotNull(floorV2);
diff --git a/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_2600/Issue2685.java b/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_2600/Issue2685.java
index 4b51a1f68..3ee18fa4a 100644
--- a/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_2600/Issue2685.java
+++ b/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_2600/Issue2685.java
@@ -6,6 +6,7 @@ import com.alibaba.fastjson.parser.DefaultJSONParser;
 import com.alibaba.fastjson.parser.JSONToken;
 import com.alibaba.fastjson.parser.deserializer.ObjectDeserializer;
 import com.alibaba.fastjson.serializer.StringCodec;
+import com.alibaba.fastjson2.JsonMapper;
 import com.zx.sms.codec.cmpp.msg.CmppSubmitResponseMessage;
 import com.zx.sms.codec.smgp.msg.SMGPSubmitMessage;
 import com.zx.sms.common.util.CMPPCommonUtil;
@@ -30,7 +31,7 @@ public class Issue2685 extends TestCase {
         String smsMsg = JSON.toJSONString(smgpSubmitMessage);
         // System.out.println(smsMsg);
 
-        com.alibaba.fastjson2.JSON.mixIn(SMGPSubmitMessage.class, Mixin.class);
+        JsonMapper.addMixIn(SMGPSubmitMessage.class, Mixin.class);
         smgpSubmitMessage = JSON.parseObject(smsMsg, SMGPSubmitMessage.class);
         assertEquals("hello", smgpSubmitMessage.getMsgContent());
     }
diff --git a/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_3400/Issue3436.java b/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_3400/Issue3436.java
index c3de72e86..b2bc0af81 100644
--- a/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_3400/Issue3436.java
+++ b/fastjson1-compatible/src/test/java/com/alibaba/json/bvt/issue_3400/Issue3436.java
@@ -3,12 +3,13 @@ package com.alibaba.json.bvt.issue_3400;
 import com.alibaba.fastjson.JSON;
 import com.alibaba.fastjson.annotation.JSONCreator;
 import com.alibaba.fastjson.annotation.JSONType;
+import com.alibaba.fastjson2.JsonMapper;
 import junit.framework.TestCase;
 import org.springframework.core.io.FileSystemResource;
 
 public class Issue3436 extends TestCase {
     public void test_for_issue() throws Exception {
-        com.alibaba.fastjson2.JSON.mixIn(FileSystemResource.class, FileSystemResourceMixedIn.class);
+        JsonMapper.addMixIn(FileSystemResource.class, FileSystemResourceMixedIn.class);
 
         FileSystemResource fileSystemResource = new FileSystemResource("E:\\my-code\\test\\test-fastjson.txt");
 

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./mvnw -V --no-transfer-progress -Pgen-javadoc -Pgen-dokka clean package -Dsurefire.useFile=false -Dmaven.test.skip=false -DfailIfNoTests=false || true

