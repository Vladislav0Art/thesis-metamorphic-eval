#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout b0f217a849703a453952f93b5999c557c201a4be

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/JsonPointer.java b/src/main/java/com/fasterxml/jackson/core/JsonPointer.java
index ff251034..2cef7a7a 100644
--- a/src/main/java/com/fasterxml/jackson/core/JsonPointer.java
+++ b/src/main/java/com/fasterxml/jackson/core/JsonPointer.java
@@ -56,64 +56,12 @@ public class JsonPointer
     /**********************************************************
      */
     
-    /**
-     * Constructor used for creating "empty" instance, used to represent
-     * state that matches current node.
-     */
-    protected JsonPointer() {
-        _nextSegment = null;
-        _headSegment = null;
-        _matchingPropertyName = "";
-        _matchingElementIndex = -1;
-        _asString = "";
-    }
-
-    /**
-     * Constructor used for creating non-empty Segments
-     */
-    protected JsonPointer(String fullString, String segment, JsonPointer next, JsonPointer head) {
-        _asString = fullString;
-        _nextSegment = next;
-        _headSegment = head;
-        // Ok; may always be a property
-        _matchingPropertyName = segment;
-        _matchingElementIndex = _parseIndex(segment);
-    }
-    
     /*
     /**********************************************************
     /* Factory methods
     /**********************************************************
      */
     
-    /**
-     * Factory method that parses given input and construct matching pointer
-     * instance, if it represents a valid JSON Pointer: if not, a
-     * {@link IllegalArgumentException} is thrown.
-     * 
-     * @throws IllegalArgumentException Thrown if the input does not present a valid JSON Pointer
-     *   expression: currently the only such expression is one that does NOT start with
-     *   a slash ('/').
-     */
-    public static JsonPointer compile(String input) throws IllegalArgumentException
-    {
-        // First quick checks for well-known 'empty' pointer
-        if ((input == null) || input.length() == 0) {
-            return EMPTY;
-        }
-        // And then quick validity check:
-        if (input.charAt(0) != '/') {
-            throw new IllegalArgumentException("Invalid input: JSON Pointer expression must start with '/': "+"\""+input+"\"");
-        }
-        return _parseTailAndHead(input);
-    }
-
-    /**
-     * Alias for {@link #compile}; added to make instances automatically
-     * deserializable by Jackson databind.
-     */
-    public static JsonPointer valueOf(String input) { return compile(input); }
-
     /* Factory method that composes a pointer instance, given a set
      * of 'raw' segments: raw meaning that no processing will be done,
      * no escaping may is present.
@@ -142,49 +90,51 @@ public class JsonPointer
     /**********************************************************
      */
 
-    public boolean matches() { return _nextSegment == null; }
-    public String getMatchingProperty() { return _matchingPropertyName; }
-    public int getMatchingIndex() { return _matchingElementIndex; }
-    public boolean mayMatchProperty() { return _matchingPropertyName != null; }
-    public boolean mayMatchElement() { return _matchingElementIndex >= 0; }
+    /*
+    /**********************************************************
+    /* Standard method overrides
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods
+    /**********************************************************
+     */
 
     /**
+     * Alias for {@link #compile}; added to make instances automatically
+     * deserializable by Jackson databind.
+     */
+    public static JsonPointer valueOf(String input) { return compile(input); }@Override public String toString() { return _asString; } /**
+     * Accessor for getting a "sub-pointer", instance where current segment
+     * has been removed and pointer includes rest of segments.
+     * For matching state, will return null.
+     */
+    public JsonPointer tail() {
+        return _nextSegment;
+    }public boolean mayMatchProperty() { return _matchingPropertyName != null; }public boolean mayMatchElement() { return _matchingElementIndex >= 0; } /**
      * Method that may be called to see if the pointer would match property
      * (of a JSON Object) with given name.
-     * 
+     *
      * @since 2.5
      */
     public boolean matchesProperty(String name) {
         return (_nextSegment != null) && _matchingPropertyName.equals(name);
-    }
-    
-    public JsonPointer matchProperty(String name) {
-        if (_nextSegment == null || !_matchingPropertyName.equals(name)) {
-            return null;
-        }
-        return _nextSegment;
-    }
-
-    /**
+    } /**
      * Method that may be called to see if the pointer would match
      * array element (of a JSON Array) with given index.
-     * 
+     *
      * @since 2.5
      */
     public boolean matchesElement(int index) {
         return (index == _matchingElementIndex) && (index >= 0);
-    }
-
-    /**
-     * Accessor for getting a "sub-pointer", instance where current segment
-     * has been removed and pointer includes rest of segments.
-     * For matching state, will return null.
-     */
-    public JsonPointer tail() {
+    }public boolean matches() { return _nextSegment == null; }public JsonPointer matchProperty(String name) {
+        if (_nextSegment == null || !_matchingPropertyName.equals(name)) {
+            return null;
+        }
         return _nextSegment;
-    }
-
-    /**
+    } /**
      * Accessor for getting a "pointer", instance from current segment to
      * segment before segment leaf. For root pointer, will return null.
      *
@@ -192,53 +142,32 @@ public class JsonPointer
      */
     public JsonPointer head() {
         return _headSegment;
-    }
-
-    /*
-    /**********************************************************
-    /* Standard method overrides
-    /**********************************************************
-     */
-
-    @Override public String toString() { return _asString; }
-    @Override public int hashCode() { return _asString.hashCode(); }
-
-    @Override public boolean equals(Object o) {
+    }@Override public int hashCode() { return _asString.hashCode(); }public String getMatchingProperty() { return _matchingPropertyName; }public int getMatchingIndex() { return _matchingElementIndex; }@Override public boolean equals(Object o) {
         if (o == this) return true;
         if (o == null) return false;
         if (!(o instanceof JsonPointer)) return false;
         return _asString.equals(((JsonPointer) o)._asString);
-    }
-    
-    /*
-    /**********************************************************
-    /* Internal methods
-    /**********************************************************
+    } /**
+     * Factory method that parses given input and construct matching pointer
+     * instance, if it represents a valid JSON Pointer: if not, a
+     * {@link IllegalArgumentException} is thrown.
+     *
+     * @throws IllegalArgumentException Thrown if the input does not present a valid JSON Pointer
+     *   expression: currently the only such expression is one that does NOT start with
+     *   a slash ('/').
      */
-
-    private final static int _parseIndex(String str) {
-        final int len = str.length();
-        // [Issue#133]: beware of super long indexes; assume we never
-        // have arrays over 2 billion entries so ints are fine.
-        if (len == 0 || len > 10) {
-            return -1;
-        }
-        for (int i = 0; i < len; ++i) {
-            char c = str.charAt(i);
-            if (c > '9' || c < '0') {
-                return -1;
-            }
+    public static JsonPointer compile(String input) throws IllegalArgumentException
+    {
+        // First quick checks for well-known 'empty' pointer
+        if ((input == null) || input.length() == 0) {
+            return EMPTY;
         }
-        if (len == 10) {
-            long l = NumberInput.parseLong(str);
-            if (l > Integer.MAX_VALUE) {
-                return -1;
-            }
+        // And then quick validity check:
+        if (input.charAt(0) != '/') {
+            throw new IllegalArgumentException("Invalid input: JSON Pointer expression must start with '/': "+"\""+input+"\"");
         }
-        return NumberInput.parseInt(str);
-    }
-    
-    protected static JsonPointer _parseTailAndHead(String input) {
+        return _parseTailAndHead(input);
+    }protected static JsonPointer _parseTailAndHead(String input) {
         final int end = input.length();
 
         int lastSlash = input.lastIndexOf('/');
@@ -264,12 +193,10 @@ public class JsonPointer
         }
         // end of the road, no escapes
         return new JsonPointer(input, input.substring(1), EMPTY, EMPTY);
-    }
-
-    /**
+    } /**
      * Method called to parse tail of pointer path, when a potentially
      * escaped character has been seen.
-     * 
+     *
      * @param input Full input for the tail being parsed
      * @param i Offset to character after tilde
      */
@@ -303,9 +230,27 @@ public class JsonPointer
         }
         // end of the road, last segment
         return new JsonPointer(input, sb.toString(), EMPTY, EMPTY);
-    }
-    
-    private static void _appendEscape(StringBuilder sb, char c) {
+    }private final static int _parseIndex(String str) {
+        final int len = str.length();
+        // [Issue#133]: beware of super long indexes; assume we never
+        // have arrays over 2 billion entries so ints are fine.
+        if (len == 0 || len > 10) {
+            return -1;
+        }
+        for (int i = 0; i < len; ++i) {
+            char c = str.charAt(i);
+            if (c > '9' || c < '0') {
+                return -1;
+            }
+        }
+        if (len == 10) {
+            long l = NumberInput.parseLong(str);
+            if (l > Integer.MAX_VALUE) {
+                return -1;
+            }
+        }
+        return NumberInput.parseInt(str);
+    }private static void _appendEscape(StringBuilder sb, char c) {
         if (c == '0') {
             c = '~';
         } else if (c == '1') {
@@ -314,5 +259,24 @@ public class JsonPointer
             sb.append('~');
         }
         sb.append(c);
-    }
-}
+    } /**
+     * Constructor used for creating "empty" instance, used to represent
+     * state that matches current node.
+     */
+    protected JsonPointer() {
+        _nextSegment = null;
+        _headSegment = null;
+        _matchingPropertyName = "";
+        _matchingElementIndex = -1;
+        _asString = "";
+    } /**
+     * Constructor used for creating non-empty Segments
+     */
+    protected JsonPointer(String fullString, String segment, JsonPointer next, JsonPointer head) {
+        _asString = fullString;
+        _nextSegment = next;
+        _headSegment = head;
+        // Ok; may always be a property
+        _matchingPropertyName = segment;
+        _matchingElementIndex = _parseIndex(segment);
+    }}

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-core/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
