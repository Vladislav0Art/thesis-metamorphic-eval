---------- Claude Sonnet 4.6 ----------

## Overview

Claude Sonnet 4.6 was run on 20 Java Multi-SWE-bench instances across 5 metamorphic transformation strategies (5 runs each = 100 agent runs per strategy). Trajectories are located under `artifacts/results/eval/{strategy}/java_20_sonnet4.6_cost_3.0_runs_5/run-{N}/trajectories/claude-sonnet-4-6__java_{strategy}_20__default__t-1.00__p-0.95__c-3.00__install-1/`.

**Trajectory format note:** Unlike GPT-5.4, Claude Sonnet 4.6 trajectories contain a lightweight `thought` field (not extended thinking tokens). Actions are native bash shell commands (`find . -name`, `grep -r`, `open`, `edit`+`end_of_edit`). The agent routinely compiles before running tests: `./gradlew compileJava` then `./gradlew test --tests ...`. This compile-first pattern distinguishes Claude from GPT-5.4, which used SWE-agent's custom `search_dir` action rather than raw shell.

---

## === s0-original ===

**Transformation:** None — original unmodified code and original problem statement.

**Resolved instances:** elastic__logstash-16681 (R1,R2,R3,R4,R5), fasterxml__jackson-core-183 (R1,R2,R3,R4,R5), mockito__mockito-3129 (R1,R2,R3,R4,R5), google__gson-1093 (R2,R3,R4,R5), elastic__logstash-14970 (R3)

**Notable vs GPT-5.4:** Claude solves elastic__logstash-16681 5/5 in s0 (GPT-5.4: 1/5). Claude solves mockito__mockito-3129 5/5 (GPT-5.4: 1/5). google__gson-1093 is 4/5 (GPT-5.4: 2/5). Step counts are dramatically lower: 8–46 steps vs GPT-5.4's 30–70+.

---

### elastic__logstash-16681

**[run-1]** _(21 steps, exit_status: submitted)_
1. First action: `find_file "PipelineBusV2.java"` — succeeds immediately. Agent opens the file and scrolls through it 5 times to understand the synchronization structure before editing.
2. Also locates `AddressState.java` via `find_file "AddressState.java"` and `PipelineBusV2Test.java` via `find_file "PipelineBusV2Test.java"`. Reading both the inner state class and the test class before editing shows Claude's prefer-to-read-all-before-edit strategy.
3. 1 edit, 1 test run (`./gradlew :logstash-core:test --tests "org.logstash.plugins..."`). The fix is applied in one precise edit after understanding all relevant context.
4. At 21 steps this is already fast — but R2/R3/R5 are even faster (8 steps each), showing R1 was exploratory while later seeds went directly to the fix.

**[run-2]** _(8 steps, exit_status: submitted — fastest trajectory for this instance across s0)_
1. Two actions only before the fix: `find_file "PipelineBusV2.java"` and a `javac` compilation check. The agent reads the file, makes 1 edit, then verifies with a Gradle test run.
2. The `javac -cp $(find . -name "*.jar" | head -5 | tr '\n' ':')` compilation shortcut — using inline jar discovery — is seen here but not in R1. Claude discovers this efficient compilation check pattern in the R2 seed.
3. 1 edit, 1 test. At 8 steps, this is near-minimal: file discovery → read → fix → compile → test.
4. The extreme brevity (8 steps for a concurrency fix) contrasts sharply with GPT-5.4's typical 40+ steps for the same instance. Claude appears to have a clear prior on what the PipelineBusV2 synchronization bug looks like.

**[run-3]** _(8 steps, exit_status: submitted)_
1. Identical step count (8) to R2, different validation approach: `./gradlew :logstash-core:compileJava 2>&1 | tail -30` then `./gradlew :logstash-core:test --tests "*PipelineBusV2*"`. Two test commands instead of R2's one.
2. 1 search, 1 edit, 2 test runs. The two-test pattern (compile-check + full test) appears in R3, R4, R5 — suggesting later seeds learn to validate compilation before running the full suite.
3. The wildcard test target `"*PipelineBusV2*"` is used instead of the fully-qualified class name in R1/R2 — a slightly broader match that catches all related tests.

**[run-4]** _(12 steps, exit_status: submitted)_
1. Two `find` searches: `find /home/logstash -name "PipelineBusV2.java"` and `find /home/logstash -name "AddressState.java"`. Reads both files. The explicit `/home/logstash` prefix (absolute path) differs from R1/R2's relative paths — the seed affects path style.
2. 1 edit, 3 test runs (compileJava + compileTestJava + full test). Most thorough validation in s0 for this instance.
3. 12 steps total — slightly more than R2/R3 due to the additional AddressState read, which gives the agent context about the inner class's lock hierarchy before editing.

**[run-5]** _(8 steps, exit_status: submitted)_
1. Single search: `find /home/logstash -name "PipelineBusV2.java"`. The most direct path: find → read → edit → compile → test.
2. 1 edit, 2 test runs. Pattern mirrors R3.
3. All 5 s0 runs use only 1 edit to fix the concurrency bug — strong evidence Claude has a precise understanding of the synchronization fix required. GPT-5.4 used 2–9 edits for this instance.

---

### fasterxml__jackson-core-183

**[run-1]** _(17 steps, exit_status: submitted)_
1. Single search: `find_file "TextBuffer.java" src`. Finds the implementation immediately. The agent reads it and makes 2 edits to `getTextBuffer()` — the consistency repair between the internal char array and the returned content.
2. Two test commands: first a custom `javac`-based spot check (`mvn compile -q && javac -cp target/classes TestTextBuffer.java && java -cp target/classes TestTextBuffer`), then a full `mvn test -q`. The javac spot check is a lightweight in-place test before committing to the full Maven suite.
3. 2 edits, 2 tests, 17 steps — highly efficient for a TextBuffer consistency fix.

**[run-2]** _(18 steps, exit_status: submitted)_
1. Two searches: `find_file "TextBuffer.java" src` then `find_file "TextBuffer" src/test` (looking for the test class). R2 explicitly locates the test class before writing the fix — a test-first awareness not seen in R1.
2. Uses `mvn test -Dtest=TextBufferTest -q` as the first test command (targeted) then `mvn test -q` (full suite). More targeted than R1's javac spot check.
3. 2 edits, 2 tests, 18 steps. Nearly identical to R1 but with a test-class search.

**[run-3]** _(17 steps, exit_status: submitted)_
1. Two searches: `TextBuffer.java` then `BufferRecycler.java`. The `BufferRecycler` class manages buffer lifecycle and is referenced in `TextBuffer` — reading it gives context on how buffers are recycled between uses, relevant to the consistency bug.
2. Custom javac spot check → `mvn test`. Same 2-edit, 2-test pattern as R1/R2.

**[run-4]** _(20 steps, exit_status: submitted)_
1. Two searches: `TextBuffer.java` and `BufferRecycler.java` (same as R3). 3 files opened (slightly more exploration).
2. 2 edits, 2 tests. The extra 3 steps vs R3 come from a more detailed read of `BufferRecycler` before editing.

**[run-5]** _(16 steps, exit_status: submitted — shortest for this instance in s0)_
1. Single search: `find_file "TextBuffer.java"`. Minimal exploration.
2. Custom javac spot check → `mvn test -q`. 2 edits, 2 tests in 16 steps — the most efficient run.
3. **Cross-instance pattern**: All 5 s0 runs use exactly 2 edits, 2 tests, find `TextBuffer.java` as the only required entry point. Step count varies 16–20 purely based on whether `BufferRecycler.java` is also read. This is the most consistent fix pattern in the dataset.

---

### mockito__mockito-3129

**[run-1]** _(30 steps, exit_status: submitted)_
1. Three searches: `find_file "MockUtil.java" src`, `find_file "MockitoPlugins.java" src`, `find_file "DefaultMockitoPlugins.java" src`. Claude always starts by locating all three key files before editing — a read-all-context-first strategy.
2. 6 edits, 4 test runs. The higher edit count (vs TextBuffer's 2) reflects the multi-file nature of the plugin system change: `MockUtil`, `MockitoPlugins` interface, and `DefaultMockitoPlugins` implementation all need coordinated edits.
3. Test sequence: `compileJava` → `gradlew test` → `gradlew :test --tests "*MockitoPlugins*"` → targeted. The progressive narrowing of test scope is a validation pattern unique to Claude (GPT-5.4 used broad tests throughout).

**[run-2]** _(39 steps, exit_status: submitted)_
1. Thirteen searches — the most of any s0 run for this instance. Includes `find src -name "MockMakers.java"` (twice), `grep -r "MockitoPlugins" src --include="*.java" -l`, and — uniquely — `find build/reports/tests -name "*.xml" | xargs grep -l "FAILED|failure|error"`. The last search reads test failure reports directly from the build directory.
2. The failure-report search `find build/reports/tests ...` reveals Claude can read Gradle's XML test reports when tests fail mid-trajectory, then react to the specific failures. This is a more sophisticated debugging loop than GPT-5.4's edit-test-repeat cycle.
3. 5 edits, 5 tests, 39 steps. More expensive than R1 but still resolves correctly.

**[run-3]** _(26 steps, exit_status: submitted — shortest for mockito in s0)_
1. Same 3-file search as R1: `MockUtil.java`, `MockitoPlugins.java`, `DefaultMockitoPlugins.java`.
2. Only 3 edits (vs R1's 6 and R2's 5) — the most surgical fix. R3's seed finds the minimal change set that satisfies the plugin interface contract.
3. 4 test runs: compileJava → test → compileTestJava → test again. The redundant compile-test-compile-test cycle suggests the agent saw a test compilation failure mid-run and recovered.

**[run-4]** _(32 steps, exit_status: submitted)_
1. Same 3-file search pattern. 5 edits, 4 tests.
2. Includes `./gradlew :compileTestJava 2>&1 | tail -20` as an intermediate validation step — checking that the test code compiles after each edit batch, before running the full test suite.

**[run-5]** _(46 steps, exit_status: submitted — longest for mockito in s0)_
1. Six searches, including `find . -name "DefaultMockitoPluginsTest.java"` (looking for the test class by name) and `grep -n "getMockMaker" src/main/java/.../MockUtil.java` and `grep -n "getMockMaker" src/main/java/.../DefaultMockitoPlugins.java`. The grep searches look for the specific method in two files simultaneously — a targeted API-surface search.
2. 10 edits, 8 test runs — the most of any s0 mockito run. The agent cycles through more fix iterations, but all converge to the correct solution.
3. All 5 s0 runs succeed. The variation (26–46 steps, 3–10 edits) shows high within-strategy variance for this instance — the fix is non-trivial but always reachable for Claude in s0.

**Cross-strategy insight (why Claude succeeds 5/5 in s0 while GPT-5.4 only succeeded 1/5):** Claude starts every run by opening all three relevant files (MockUtil, MockitoPlugins, DefaultMockitoPlugins) before making any edit. This systematic read-first approach prevents the cyclic edit loop GPT-5.4 fell into (where it would edit MockUtil.java repeatedly without reading the interface). Claude's `compileJava` step after edits also catches compilation errors early, allowing correction before the test suite runs.

---

### google__gson-1093

**[run-2]** _(9 steps, exit_status: submitted — ultra-efficient)_
1. Single search: `find_file "JsonWriter.java" gson`. Opens the file directly. 2 edits to the `value(double)` method's formatting logic. 1 test run: `cd /home/gson && mvn test -pl gson -Dtest=JsonWriterTest -q`.
2. 9 steps total — comparable to elastic__logstash-16681's fastest runs. Claude treats this as a trivial fix: one targeted file, one method, one test.

**[run-3]** _(8 steps, exit_status: submitted — shortest gson trajectory)_
1. Single search: `find_file "JsonWriter.java"`. 1 edit (more precise than R2's 2). Same test command.
2. R3 solves it in 1 edit — the most surgical fix across all runs. This is the minimum viable fix: the exact format-string change in `value(double)` with no surrounding changes.

**[run-4]** _(13 steps, exit_status: submitted)_
1. Single search: `find_file "JsonWriter.java" gson`. 3 edits (the most for gson in s0), 2 tests. The second test uses a custom `javac` spot check: `mvn compile -pl gson -q && javac -cp gson/target/classes /tmp/TestDouble.java`.
2. More iterations than R2/R3 — R4's seed attempts a more comprehensive fix covering multiple edge cases in double formatting. The custom test verifies a specific double-to-string edge case.

**[run-5]** _(14 steps, exit_status: submitted)_
1. Two searches: `find_file "JsonWriter.java" gson` and `find_file "JsonWriterTest.java"`. R5 is the only s0 gson run that explicitly locates the test file — R2/R3/R4 infer its location from the Maven test command.
2. 2 edits, 2 test runs. The test file read informs a slightly different fix structure.

**Cross-strategy insight (why gson fails under s1/s4):** The gson fix is anchored entirely to `JsonWriter.java`. Under s1/s4 (renaming), this class is renamed. Claude's `find_file "JsonWriter.java"` fails immediately, and unlike elastic__logstash-16681, there is no meaningful fallback — the double-formatting bug cannot be found by method name or content search without knowing the class name. The 0/5 failure under s1/s4 for both Claude and GPT-5.4 confirms this class-name anchoring is the fundamental fragility.

---

### elastic__logstash-14970

**[run-3]** _(27 steps, exit_status: submitted — only s0 resolved run)_
1. Three searches: `find_file "DeadLetterQueueWriter.java"`, `find_file "RecordIOReader.java" logstash-core/src/main/java/org/logstash/common/io`, and `find_file "DeadLetterQueueWriterTest.java"`. Claude reads the writer, the segment reader (to understand the segment format), and the test class.
2. The `RecordIOReader.java` search is significant: it's the class that reads segment headers. Understanding the header format (VERSION byte = 1 byte) is necessary to diagnose why `lastBlockId` goes negative for a 1-byte segment.
3. 2 edits (guard + regression test), 2 test runs. Scrolls through files 4 times to track the segment-reading logic across multiple methods.
4. This is the only s0 run that resolves — 4 of 5 runs fail. Claude can solve the DLQ bug but with much lower consistency than elastic__logstash-16681, reflecting the higher diagnostic complexity (segment format understanding required).

---

## === s1-renaming ===

**Transformation:** Identifiers (class names, method names, variable names) in the changed files are renamed. Problem statement is also updated to use new names.

**Resolved instances:** elastic__logstash-16681 (R1,R2,R3,R4,R5), fasterxml__jackson-core-183 (R1,R3,R4,R5), mockito__mockito-3129 (R1,R2,R3,R4,R5), fasterxml__jackson-databind-1923 (R2)

**Notable improvements:** fasterxml__jackson-databind-1923 unlocked (was 0/5 in s0 → 1/5 in s1)

**Instances that dropped:** google__gson-1093 (4/5 → 0/5), fasterxml__jackson-core-183 (5/5 → 4/5, lost R2), elastic__logstash-14970 (1/5 → 0/5)

---

### elastic__logstash-16681

**[run-1]** _(22 steps, exit_status: submitted)_
1. Seven searches — substantially more than s0's 1–2. Begins with `find_file "PipelineEventBusV2.java"` (the renamed class) which fails. Then escalates: `find / -name "PipelineEventBusV2.java"` (filesystem-wide), `find logstash-core -name "*.java" | xargs grep -l "PipelineEventBusV2"` (content search), `find logstash-core -name "*.java" | xargs grep -l "PipelineEventBus|PipelineBus"` (broadened name variants), and finally a `javac` compilation attempt to see what class names are available.
2. The content-based fallback (`xargs grep -l`) is the key recovery mechanism. Unlike GPT-5.4 which gave up after consecutive zero-result searches, Claude programmatically broadens its search at each failure, eventually finding `PipelineBusV2.java` via the content match on `PipelineEventBus` substring.
3. Also finds `AddressState.java` and the test class. 1 edit, 4 test runs. The higher test count (vs s0's 1–3) reflects the extra validation needed after searching longer.
4. 22 steps vs s0 R1's 21 — nearly the same total budget despite 7x more searches, because the searches replace exploratory file reads.

**[run-2]** _(25 steps, exit_status: submitted)_
1. Nine searches — the most of any s1 run for this instance. Includes two directory-listing fallbacks: `find . -type d -name "pipeline"` (finding the directory by name, not file) and `find . -name "*PipelineBus*" -type f` (wildcard on partial class name).
2. The directory-search `find . -type d -name "pipeline"` is unique to R2 — it navigates to the `pipeline/` package directory and then lists its contents, discovering `PipelineBusV2.java` by directory membership rather than name or content.
3. 1 edit, 4 test runs. Same fix as s0 despite the longer search phase.

**[run-3]** _(15 steps, exit_status: submitted — shortest s1 run for this instance)_
1. Three searches: `find_file "PipelineEventBusV2.java"` → `find . -name "PipelineEventBusV2.java"` → `find . -name "PipelineBus*"`. The third search uses a glob on the partial name prefix — a more efficient fallback than R1/R2's content-search approach.
2. The `PipelineBus*` glob finds `PipelineBusV2.java` in 3 searches rather than R1's 7. This is the most efficient s1 recovery pattern.
3. 1 edit, 3 tests, 15 steps — faster than even s0 R1 (21 steps) because the shorter search phase compensates for the failed initial lookup.

**[run-4]** _(17 steps, exit_status: submitted)_
1. Seven searches including two path-based approaches: `find . -name "*.java" | head -20` (listing all Java files to browse) and `find . -path "*/plugins/pipeline*"` (traversing to the right package directory). The path-based fallback navigates the package hierarchy rather than searching by content.
2. 1 edit, 3 tests. The path-traversal approach (`*/plugins/pipeline*`) is the most architecturally-aware fallback — it relies on understanding the Logstash package structure, not just file names.

**[run-5]** _(18 steps, exit_status: submitted)_
1. Seven searches with the most creative fallback: `grep -n "notifyAll|inputToNotify|synchronized" logstash-core/src/main/java/org/logstash/plugins/pipeline/PipelineBusV2.java` — directly addressing the synchronization primitives in the suspected file, using the full absolute path. This means the agent inferred the correct path without a successful `find` result.
2. The synchronization-primitive grep is equivalent to GPT-5.4's method-based search strategy and is the only run where Claude uses content search on the suspected file before confirming the file name.
3. 1 edit, 3 tests. The path inference (`/home/logstash/logstash-core/src/main/java/org/logstash/plugins/pipeline/PipelineBusV2.java`) is correct despite all name searches failing — Claude uses its knowledge of the Logstash codebase structure.

**Cross-strategy insight (elastic__logstash-16681 5/5 under s1 vs GPT-5.4's 0/5 for DLQ instances under s1):** Every s1 Claude run for this instance follows the same cascading pattern: named search fails → filesystem-wide search → content search → path inference. The cascade takes 3–9 searches but always succeeds. GPT-5.4 on the DLQ instances (14970/14981) followed the same initial failure but had no effective fallback — it kept issuing zero-result content searches on the non-existent renamed name. Claude's fallback chain (`PipelineBus*` glob, directory traversal, path inference) provides multiple recovery paths that GPT-5.4 lacked.

---

### fasterxml__jackson-core-183

**[run-1]** _(37 steps, exit_status: submitted)_
1. Two searches: `find_file "SegmentedTextBuffer.java" src` and `find_file "SegmentedStringWriter.java" src`. Both use the renamed class name — Claude correctly infers from the problem statement that `TextBuffer` is now called `SegmentedTextBuffer` and searches for its renamed sibling `SegmentedStringWriter`.
2. The `SegmentedStringWriter` search (sibling class) is not seen in s0. The rename changes the naming pattern of the whole file, and Claude uses this to find related types.
3. 5 edits, 4 tests. More iterations than s0's 2 edits — the renamed API surface requires more edits to get all method signatures correct (the rename changes method return types and parameter type references throughout).
4. 37 steps vs s0's 17 — 2x overhead from understanding the renamed class structure.

**[run-3]** _(27 steps, exit_status: submitted)_
1. Single search: `find_file "SegmentedTextBuffer.java"`. Directly infers the renamed class from the problem statement.
2. 3 edits, 3 tests. Less overhead than R1 — R3 makes more targeted edits without exploring sibling classes.

**[run-4]** _(39 steps, exit_status: submitted)_
1. Two searches: `SegmentedTextBuffer.java` and `BufferRecycler.java`. BufferRecycler is found under its original name (buffer management classes weren't renamed). The contrast — implementation renamed, recycler unchanged — gives the agent context about which names have changed.
2. 8 edits, 4 tests — the most edits of any jackson-core-183 run across all strategies. The renamed API requires coordinating changes across more call sites.

**[run-5]** _(42 steps, exit_status: submitted)_
1. Two searches: `SegmentedTextBuffer.java` and `BufferRecycler.java`. Same as R4 but more test runs (5) and different test commands: `mvn test -pl . -Dtest=SegmentedTextBufferTest` (using the new test class name) and `mvn test -Dtest=TestTextBuffer` (checking if the old test name still works). The two test commands probe both old and new class names.
2. 7 edits, 5 tests. R5 spends the most effort on test validation — checking both the renamed test class and the original test class.
3. **Missing R2**: The 4/5 pattern (R1,R3,R4,R5 resolved, R2 missing) suggests R2's seed produces a fix that fails the final test. Given R1/R4/R5 all use 5–8 edits while R3 uses 3, R2 likely under-edits (perhaps only 1–2 edits) and misses a renamed method signature.

---

### mockito__mockito-3129

**[run-1]** _(57 steps, exit_status: submitted)_
1. Fifteen searches — by far the most of any mockito trajectory. The renamed interface is `MockitoPluginRegistry`. Searches include: `find_file "MockUtils.java"` (renamed from `MockUtil`), `find_file "MockitoPlugins.java"` (unchanged), `find_file "DefaultPluginRegistry.java"` (renamed from DefaultMockitoPlugins), `search_dir "implements MockitoPluginRegistry" src`, `find . -name "MockitoPluginRegistryTest*"`, `find . -name "MockUtilsTest*"`, `./gradlew test 2>&1 | grep "FAILED|PASS|ERROR"`, and `./gradlew test 2>&1 | grep "Test|test|fail|FAIL"`.
2. The test-output grep searches (`grep "FAILED|PASS|ERROR"`) appear after failed test runs — Claude reads the test output programmatically to identify which tests are failing before making more edits.
3. 7 edits, 10 tests — most expensive mockito trajectory. The renaming forces the agent to re-map the entire plugin system structure before it can make correct edits.

**[run-2]** _(50 steps, exit_status: submitted)_
1. Ten searches. Includes `find_file "MockitoPluginRegistry.java"`, `find_file "DefaultMockitoPluginRegistry.java"`, `search_dir "MockitoPluginRegistry" /home/mockito/src`, `search_dir "implements MockitoPluginRegistry"`, and `find_file "MockMakers.java"`. Claude is building a complete map of the renamed plugin system.
2. 7 edits, 9 tests. Both `./gradlew :mockito-core:compileJava` and `./gradlew compileJava` are tried (the subproject prefix is sometimes needed in multi-module Gradle builds).

**[run-3]** _(45 steps, exit_status: submitted)_
1. Eleven searches including a unique one: `grep -r "MockitoPluginRegistry" --include="*.java" -l .` and `grep -r "implements MockitoPluginRegistry" --include="*.java" -l .`. The content-based grep (not file-name based) finds all files that reference the renamed interface — a comprehensive implementation search.
2. Also runs `./gradlew test --tests "*MockitoPluginRegistryTest*"` — testing by the new interface name's test class. 7 edits, 7 tests.

**[run-4]** _(43 steps, exit_status: submitted)_
1. Five searches. More focused than R1–R3: `MockUtils.java`, `MockitoPlugins.java` (× 2, with and without path), `DefaultMockitoPlugins.java`, and `search_dir "MockitoPluginRegistry" src`. The repeated `MockitoPlugins.java` search (first `find_file "MockitoPlugins.java" src`, then `find_file "MockitoPlugins.java"` without path) shows refinement when the first search doesn't find the file in the expected location.
2. 9 edits (highest for s1 mockito), 5 tests. 43 steps.

**[run-5]** _(42 steps, exit_status: submitted)_
1. Eight searches, ending with `search_dir "implements MockitoPluginRegistry" src`. Finds `MockUtils.java`, both `MockitoPlugins.java` forms, `MockitoPluginRegistry.java`, `DefaultMockitoPluginRegistry.java`, and `MockitoDefaultPlugins.java` (an older name variant).
2. 7 edits, 6 tests. Runs `./gradlew :test --tests "org.mockito.internal.util.MockUtilsTest"` — targeted test by the renamed utility class's test.
3. **All 5 s1 runs resolve** — same as s0. Claude maintains 5/5 consistency for mockito despite full renaming. The cost is higher step counts (42–57 vs s0's 26–46) and more searches (5–15 vs s0's 3–6).

---

### fasterxml__jackson-databind-1923

**[run-2]** _(31 steps, exit_status: submitted — only s1 resolved run, and unlocks an instance impossible in s0)_
1. Six searches: `find_file "SubtypeValidator.java"`, `find_file "SubtypeValidatorTest.java"`, `find /home/jackson-databind/src/test -name "*.java" | xargs grep -l "SubtypeValidator|validateSubtype"`, then two Spring-stub content searches: `find /home/jackson-databind/src/test -name "*.java" | xargs grep -l "BogusApplicationContext|BogusPointcutAdvisor"` and `find /home/jackson-databind/src/test/java/org/springframework/jacksontest -type f`.
2. The Spring-stub searches (`BogusApplicationContext`, `BogusPointcutAdvisor`) are the critical step. The fix requires Spring Security test stubs to be present in the test directory. Claude uses content-based search to find these stub files, regardless of their package path — a method GPT-5.4 achieved only in s0 with prior knowledge of the path.
3. 4 edits, 3 tests (`mvn test -Dtest=IllegalTypesCheckTest`). The fix adds the new type to the illegal-types blocklist with the stubs in place.
4. **This instance fails in s0 for Claude but succeeds in s1.** The renaming of `SubtypeValidator` (possibly to a more descriptive name like `DefaultSubtypeValidator`) provides a clearer hint in the problem statement that guides the Spring-stub content search. In s0, Claude apparently searches for the stubs incorrectly or finds the validator but doesn't know to look for the Spring test infrastructure.

---

## === s2-structural ===

**Transformation:** Methods within changed files are sorted Z→A; some files may be relocated to different package directories. No identifier renaming.

**Resolved instances:** elastic__logstash-16681 (R1,R2,R3,R4,R5), fasterxml__jackson-core-183 (R1,R2,R3,R4,R5), mockito__mockito-3129 (R1,R2,R4,R5), google__gson-1093 (R2,R3,R4,R5), elastic__logstash-14970 (R3), apache__dubbo-11781 (R5), fasterxml__jackson-databind-1923 (R4)

**Notable improvements over s0:** fasterxml__jackson-databind-1923 unlocked (0/5 → 1/5), apache__dubbo-11781 unlocked (0/5 → 1/5)

**Instances that dropped:** google__gson-1093 (4/5 → 4/5, same but missing R1), mockito__mockito-3129 (5/5 → 4/5, missing R3)

---

### elastic__logstash-16681

**[run-1]** _(9 steps, exit_status: submitted — fewest steps for this instance across all strategies)_
1. Single search: `find . -name "PipelineBusV2.java" -type f`. The structural transformation doesn't rename the class, so the first search succeeds immediately. 1 edit, 3 test runs.
2. 9 steps — even faster than s0's fastest (8 steps), because the method-sorted layout may place the relevant synchronization methods at predictable positions in the file, reducing the number of scroll operations needed.
3. The 3 test runs (compileJava + full pipeline test + specific PipelineBusV2 test) are more thorough than s0's typical 1–2 test commands, reflecting increased test validation effort.

**[run-2]** _(13 steps, exit_status: submitted)_
1. Four searches: `find_file "PipelineBusV2.java"`, `find_file "PipelineBusV2Test.java"`, `find /home/logstash -name "*PipelineBus*"`, and a `javac` compilation probe. The test-file lookup is now explicit (finding `PipelineBusV2Test.java`) — the agent reads the test class to understand expected behavior before editing.
2. 1 edit, 1 test. The explicit test-class read reduces iterations: understanding the expected test behavior first produces a correct fix in 1 edit.

**[run-3]** _(10 steps, exit_status: submitted)_
1. Single search: `find_file "PipelineBusV2.java"`. 2 edits (vs R1's 1) — the structural transformation's Z→A method sorting places methods in a different order, requiring the agent to edit 2 locations that in the original order appeared as one contiguous block.
2. 2 tests: compileJava → test. Very compact.

**[run-4]** _(12 steps, exit_status: submitted)_
1. Single search. 2 edits, 3 tests (compile + two test scopes). The method-sorting effect: some runs need 1 edit (R1, R5), some need 2 (R3, R4) — depending on whether the edit spans a sort boundary.

**[run-5]** _(9 steps, exit_status: submitted)_
1. Single search. 1 edit, 2 tests. Tied with R1 for fastest. Structurally identical to s0's fastest runs.
2. **Overall**: elastic__logstash-16681 under s2 is marginally faster than s0 (9–13 steps vs 8–21). The structural transformation has near-zero impact on Claude's ability to solve this instance — class names are unchanged and `find_file` succeeds on the first try in all 5 runs.

---

### fasterxml__jackson-core-183

**[run-1]** _(26 steps, exit_status: submitted)_
1. Single search: `find_file "TextBuffer.java" src`. Class name unchanged. 2 edits, 2 tests. Javac spot check → `mvn test`. Very similar to s0.
2. Slightly more steps than s0 R1 (26 vs 17) — the Z→A sorted method order requires more scrolling to locate `getTextBuffer()` since it no longer appears at its original position.

**[run-2]** _(23 steps, exit_status: submitted)_
1. Single search: `find_file "TextBuffer.java" src`. 2 edits, 2 tests. 23 steps.

**[run-3]** _(21 steps, exit_status: submitted)_
1. Two searches: `TextBuffer.java` and `BufferRecycler.java`. 2 edits, 2 tests. The `cd /home/jackson-core &&` prefix on the test command shows the agent navigating to the project root before running Maven.

**[run-4]** _(23 steps, exit_status: submitted)_
1. Two searches: `TextBuffer.java` and `find_file "TextBufferTest.java" src`. Explicitly finding the test class (as in s0 R2). 1 edit (the most targeted fix: just the `getTextBuffer()` return value correction), 2 tests. The least-edit run across all jackson-core-183 trajectories.

**[run-5]** _(20 steps, exit_status: submitted)_
1. Two searches: `TextBuffer.java` and `BufferRecycler.java`. 2 edits, 2 tests. Javac spot check → `mvn test`. Shortest s2 run for this instance.
2. **All 5 s2 runs succeed**. Step counts (20–26) are higher than s0 (16–20) but consistent. The Z→A sort adds a small navigation overhead but doesn't prevent correct fixes.

---

### mockito__mockito-3129

**[run-1]** _(38 steps, exit_status: submitted)_
1. Ten searches — more than s0's 3–6. Includes searches for `MockitoPluginsImpl.java` (a possible renamed implementation), `search_dir "getInlineMockMaker" src`, and — uniquely — `find build/reports/tests -name "*.xml" | xargs grep -l "FAILED|failure|error"` and `find build/reports/tests -name "*.html"`. Claude reads the Gradle test report HTML files to diagnose failures.
2. The test-report HTML reading pattern (`find build/reports/tests -name "*.html"`) is a sophisticated debugging technique: instead of running tests in verbose mode, Claude navigates the existing test report artifact.
3. 3 edits, 9 tests — the highest test count for mockito under s2. The test-report approach requires more test cycles to get fresh reports after each edit.

**[run-2]** _(35 steps, exit_status: submitted)_
1. Four searches: `MockUtil.java`, `MockitoPlugins.java`, `DefaultMockitoPlugins.java`, `find /home/mockito -name "MockUtil.java" -type f` (absolute path fallback when the relative search doesn't find the file). Structural transformation may have moved `MockUtil.java` to a different subproject directory.
2. 8 edits, 4 tests. Slightly heavier edit count than s0 — the file relocation causes the agent to make extra edits to import paths.

**[run-4]** _(30 steps, exit_status: submitted)_
1. Three searches: `MockUtil.java`, `MockitoPlugins.java`, `DefaultMockitoPlugins.java`. Same as s0's baseline pattern. 5 edits, 7 tests. The high test count (7) reflects aggressive validation: `./gradlew test --tests "org.mockito.internal.configuration.plugins.*"` run multiple times.

**[run-5]** _(29 steps, exit_status: submitted)_
1. Five searches, ending with `grep -r "implements MockitoPlugins" src --include="*.java" -l`. This interface-implementation search is a path-agnostic way to find the implementing class even if it moved directories under s2.
2. 5 edits, 4 tests. At 29 steps, the most efficient s2 mockito run.
3. **Missing R3**: 4/5 under s2 (vs 5/5 in s0). The structural transformation appears to cause one seed (R3) to fail — likely due to the file relocation disrupting the agent's edit path or import resolution. The fact that 4 seeds still succeed shows the structural change is minor for this instance.

---

### google__gson-1093

**[run-2]** _(16 steps, exit_status: submitted)_
1. Single search: `find_file "JsonWriter.java"`. 3 edits (more than s0's 1–2), 2 tests. The structural transformation (Z→A sort) places the `value(double)` method at a different position in the file. The agent makes extra edits to handle the value method's sorted neighbors correctly.
2. The second test uses `mvn package -pl gson -DskipTests -q` — checking package assembly rather than just unit tests. This broader validation is new in s2.

**[run-3]** _(16 steps, exit_status: submitted)_
1. Two searches: `JsonWriter.java` and `find_file "JsonWriterTest.java"`. 4 edits, 3 tests. More iterations than s0 — the Z→A sort changes the position of test-related methods in `JsonWriterTest.java`, requiring extra edits to handle neighboring methods.

**[run-4]** _(8 steps, exit_status: submitted — shortest s2 gson run)_
1. Single search. 2 edits, 1 test. Very compact — R4's seed reaches the fix directly without needing the test class.

**[run-5]** _(9 steps, exit_status: submitted)_
1. Single search. 1 edit, 2 tests. The most surgical gson fix under s2.
2. **Missing R1**: 4/5 under s2. The R1 failure under structural transformation for gson suggests the Z→A sort places a critical method or constant in a position that causes the agent's first edit to be incorrect for that seed.

---

### elastic__logstash-14970

**[run-3]** _(17 steps, exit_status: submitted — only s2 resolved run, 10 fewer steps than s0's R3)_
1. Three searches: `find . -name "DeadLetterQueueWriter.java"`, `find . -name "RecordIOReader.java"`, and `find . -name "DeadLetterQueueWriterTest.java"`. Same three-file lookup as s0 R3.
2. 1 edit (vs s0's 2), 2 tests. The structural transformation (Z→A sort) places `readTimestampOfLastEventInSegment` at a more predictable position in the sorted file, allowing the agent to identify and fix it in 1 edit rather than 2.
3. 17 steps vs s0's 27 — 37% faster. The method-sorting paradoxically makes the target method easier to locate and fix.
4. Same 1/5 consistency as s0 — the instance remains hard regardless of structural changes.

---

### apache__dubbo-11781

**[run-5]** _(58 steps, exit_status: submitted via exit_cost — unique: only run to solve this instance across all strategies and both models)_
1. Ten searches: `find_file "URL.java" dubbo-common`, `search_dir "parseQueryString|parseParameters|splitQuery" dubbo-common/src/main/java`, `find_file "URL.java" dubbo-common/src/main/java`, `find_file "URLParam.java"`, `find_file "URLStrParser.java"`, `find_file "URLStrParserTest.java"`, `grep -n "checkstyle|dubbo-build-tools" dubbo-common/pom.xml`, and a similar pom.xml grep at root level.
2. The `pom.xml` checkstyle/build-tools grep is unique — Claude is checking whether the Dubbo build has checkstyle enforcement, likely to understand why its edits might fail compilation. This is a build-system awareness step not seen in any other trajectory.
3. 4 edits, 0 test runs. The agent hits the cost limit before running any tests. The submitted patch is correct — a serendipitous resolution similar to elastic__logstash-16579 in GPT-5.4's s3.
4. The URL parsing issue in Dubbo requires navigating a complex URL parameter encoding system (`URLParam`, `URLStrParser`) across multiple classes. 10 searches across these classes map the full URL parsing pipeline.
5. **Why only s2 and only R5?** The structural transformation (Z→A method sort) of `URL.java` and related classes may have simplified the parameter parsing logic's presentation — sorted methods put the failing parse path first in the file, making it easier for the agent to identify the bug surface. The exit_cost indicates the fix is near-budget-limit and only the specific code path that R5's seed chose happened to produce a correct patch.

---

### fasterxml__jackson-databind-1923

**[run-4]** _(14 steps, exit_status: submitted — shortest resolved trajectory for this instance across all strategies)_
1. Six searches: `find_file "SubTypeValidator.java"`, `find_file "SubTypeValidatorTest.java"`, `find_file "TestSubTypeValidator.java"`, `search_dir "SubTypeValidator" /home/jackson-databind/src/test`, `search_dir "validateSubType" /home/jackson-databind/src/test`, `search_dir "enableDefaultTyping" /home/jackson-databind/src/test`. All searches target the validator and its test infrastructure.
2. The content-based searches (`validateSubType`, `enableDefaultTyping`) find the test class `IllegalTypesCheckTest` without needing to navigate the Spring stub directories. The structural transformation may have moved the test file to a flatter directory structure, making content search more direct.
3. 1 edit, 1 test (`mvn test -Dtest=IllegalTypesCheckTest`). At 14 steps, this is the most efficient resolution of this instance across all trajectories. The structural transformation appears to make the fix surface clearer — possibly by reordering the validator methods so the blocklist management code appears first.
4. **Why does s2 unlock this when s0 cannot?** The Z→A method sort in `SubTypeValidator.java` (or its structural equivalent) may place the `isIllegal()` method check near the top of the file, making it the first thing the agent reads. In s0, the method appears after many unrelated methods, and the agent may exhaust its context before reaching it.

---

## === s3-problem-statement ===

**Transformation:** Only the problem statement text is rewritten — code is identical to s0.

**Resolved instances:** elastic__logstash-16681 (R1,R2,R3,R4,R5), fasterxml__jackson-core-183 (R2,R3,R4,R5), mockito__mockito-3129 (R1,R2,R3,R4,R5), google__gson-1093 (R1,R2,R3,R4), elastic__logstash-14970 (R2)

**Notable improvements over s0:** google__gson-1093 unlocks R1 (4/5 → 4/5 but with different missing run — R5 instead of R1), elastic__logstash-14970 solved in R2 (vs s0's R3)

**Instances that dropped:** fasterxml__jackson-core-183 (5/5 → 4/5, missing R1)

---

### elastic__logstash-16681

**[run-1]** _(12 steps, exit_status: submitted)_
1. Two searches: `find /home/logstash -name "PipelineBusV2.java"` and `find /home/logstash -name "AddressState.java"`. The problem-statement rewrite provides explicit mention of the `AddressState` inner class, causing the agent to look it up in addition to the main class.
2. 1 edit, 3 tests. The `AddressState` context (from the rewritten problem statement) leads to a more targeted fix of the state-transition logic, validated with 3 test commands.

**[run-2]** _(9 steps, exit_status: submitted)_
1. Two searches: `find_file "PipelineBusV2.java"` then `find /home/logstash -name "*.java" -path "*/plugins/pipeline/*"`. The second search lists all pipeline-package Java files — the rewritten problem statement may reference multiple classes in the pipeline package, prompting the full package scan.
2. 1 edit, 1 test. 9 steps — as compact as s2's fastest.

**[run-3]** _(14 steps, exit_status: submitted)_
1. Four searches: `PipelineBusV2.java`, `PipelineBusV2Test.java`, `find . -path "*test*" -name "*PipelineBus*"`, and `AddressState.java`. The explicit test-class searches (both name-based and path-filtered) reflect the rewritten problem statement's test-focused framing.
2. 1 edit, 2 tests.

**[run-4]** _(12 steps, exit_status: submitted)_
1. Two searches: `PipelineBusV2.java` and `AddressState.java`. 1 edit, 3 tests. Same pattern as R1 — the AddressState lookup is consistent across seeds when the problem statement highlights it.

**[run-5]** _(12 steps, exit_status: submitted)_
1. Four searches: `PipelineBusV2.java`, `find /home/logstash/logstash-core -name "*.java" -path "*/pipeline/Pipeline*"`, `AddressState.java`, and a `javac` check. The pipeline-package path filter is from R2; `AddressState` is from R1/R4. R5 combines both.
2. 1 edit, 2 tests. Consistent with the overall s3 pattern for this instance.

---

### fasterxml__jackson-core-183

**[run-2]** _(16 steps, exit_status: submitted)_
1. Single search: `find_file "TextBuffer.java" src`. 2 edits, 2 tests. Same minimal pattern as s0. Code is unchanged under s3, so navigation is identical.

**[run-3]** _(16 steps, exit_status: submitted)_
1. Single search. 2 edits, 2 tests. Identical to R2.

**[run-4]** _(21 steps, exit_status: submitted)_
1. Two searches: `TextBuffer.java` and `TextBufferTest.java`. 2 edits, 2 tests. R4 explicitly finds the test class — the rewritten problem statement may reference test scenarios that guide this lookup.

**[run-5]** _(17 steps, exit_status: submitted)_
1. Single search. 2 edits, 2 tests. Compact.
2. **Missing R1**: 4/5 under s3. R1 uniquely fails under the rewritten problem statement — the rewrite may use terminology that misdirects R1's seed, causing an incorrect fix. This contrasts with s0 where R1 was the first successful run.

---

### mockito__mockito-3129

**[run-1]** _(44 steps, exit_status: submitted)_
1. Ten searches. Includes a search for `MockitoPluginsImpl.java` (looking for an implementation class that may not exist under that name), `search_dir "getInlineMockMaker" src`, and — uniquely — reading the Gradle test report HTML: `cat build/reports/tests/retryTest/classes/org.mockito.internal.junit.UnusedStubbingsTest.html | grep ...`. This is the only trajectory across the entire dataset that reads a test report HTML file by `cat`-ing its contents.
2. 7 edits, 8 tests. Most expensive mockito R1 across all strategies.
3. The `UnusedStubbingsTest.html` report read reveals Claude's precise debugging approach: it reads the HTML of a specific failing test class to understand what the stubbing setup expects, then edits accordingly.

**[run-2]** _(47 steps, exit_status: submitted)_
1. Four searches: `MockUtil.java`, `MockitoPlugins.java`, `DefaultMockitoPlugins.java`, and `find_file "Plugins.java" src`. The `Plugins.java` search is unique — the rewritten problem statement may reference a `Plugins` utility class not mentioned in s0's problem statement.
2. 11 edits — the most of any mockito trajectory across all strategies. 5 tests. The `Plugins.java` context causes the agent to make additional edits to the utility class in addition to the standard 3-file changes.
3. `--no-daemon` flag is added to several Gradle commands: `./gradlew compileJava --no-daemon`. This prevents Gradle daemon reuse — a practical reliability measure in the test environment.

**[run-3]** _(34 steps, exit_status: submitted)_
1. Three searches: `MockUtil.java`, `MockitoPlugins.java`, `DefaultMockitoPlugins.java`. Same minimal pattern as s0 R1/R3. 8 edits, 4 tests.

**[run-4]** _(34 steps, exit_status: submitted)_
1. Five searches, including `grep -r "implements MockitoPlugins" --include="*.java" -l` and `grep -r "getInlineMockMaker" --include="*.java" -n`. The grep-based searches are content-oriented rather than file-name oriented — finding implementations and method usages regardless of file location.
2. 7 edits, 4 tests. Uses `--no-daemon` for reliability.

**[run-5]** _(27 steps, exit_status: submitted — shortest s3 mockito run)_
1. Four searches: `MockUtil.java`, `MockitoPlugins.java`, `DefaultMockitoPlugins.java`, `MockMakers.java`. The `MockMakers.java` factory class lookup is also seen in s0 R5.
2. 5 edits, 4 tests. Compact.
3. **All 5 s3 runs resolve** (same as s0). The problem-statement rewrite doesn't hurt and slightly changes exploration patterns (more content-based greps, Plugins.java lookup) without disrupting success.

---

### google__gson-1093

**[run-1]** _(8 steps, exit_status: submitted — unlocks R1 which failed in s0)_
1. Single search: `find_file "JsonWriter.java"`. 1 edit, 1 test. 8 steps — tied for shortest gson trajectory.
2. The problem-statement rewrite apparently provides clearer framing of the double-formatting bug, allowing R1's seed (which failed in s0) to produce a correct 1-edit fix immediately.
3. **R1 unlock**: In s0, R1 fails. In s3, R1 succeeds with the minimal 1-edit fix. The rewrite resolves whatever ambiguity caused R1's s0 failure — likely a clearer specification of which double values should be formatted as integers vs decimals.

**[run-2]** _(8 steps, exit_status: submitted)_
1. Same: `find_file "JsonWriter.java"`, 1 edit, 1 test.

**[run-3]** _(9 steps, exit_status: submitted)_
1. Single search. 2 edits, 1 test. One extra edit vs R1/R2.

**[run-4]** _(20 steps, exit_status: submitted — heaviest s3 gson run)_
1. Three searches including `mvn test -pl gson 2>&1 | grep "FAILED|FAIL|Tests run"` and `mvn test -pl gson 2>&1 | grep "ERROR|FAIL"` — reading Maven test output as search queries. R4's seed encounters a test failure mid-trajectory and uses grep-based test-output scanning to diagnose it.
2. 4 edits, 5 tests. The most iterations for any gson run. The test-output scanning leads to multiple fix attempts before success.
3. **Missing R5**: 4/5 under s3. R5 fails — the most anomalous outcome for gson, which typically resolves quickly.

---

### elastic__logstash-14970

**[run-2]** _(22 steps, exit_status: submitted — only s3 resolved run)_
1. Four searches: `find . -name "DeadLetterQueueWriter.java"`, then unexpectedly `edit 410:429 ... private static Optional<Timestamp> readTimestampOfLastEventInSegment` appears as a search result (an artifact of the extraction showing an edit action containing a code snippet), `find . -name "DeadLetterQueueWriterTest.java"`, and a `javac` compilation check.
2. The `edit` action captured as a search is an extraction artifact — the agent opened the implementation file, saw the method at line 410 and immediately started editing. This shows Claude went directly to the target method without needing to search for it (the method's position was known from the file read).
3. 4 edits, 2 tests. The rewritten problem statement guided R2 (which failed in s0) to succeed — likely by clarifying the expected behavior for 1-byte segment files.
4. Solved in R2 (vs s0's R3). The specific seed that succeeds shifts between strategies, but the overall 1/5 consistency persists.

---

## === s4-combined ===

**Transformation:** All transformations simultaneously — identifier renaming (s1) + structural reorganization (s2) + problem-statement rewrite (s3).

**Resolved instances:** elastic__logstash-16681 (R1,R2,R3,R4,R5), fasterxml__jackson-core-183 (R2,R3,R4,R5), mockito__mockito-3129 (R1,R2,R4,R5), fasterxml__jackson-databind-1923 (R1,R3)

**Maintained 5/5:** elastic__logstash-16681

**Instances that dropped from s0:** google__gson-1093 (4/5 → 0/5 — renaming kills it), elastic__logstash-14970 (1/5 → 0/5), fasterxml__jackson-core-183 (5/5 → 4/5)

**New instance maintained:** fasterxml__jackson-databind-1923 (0/5 in s0 → 2/5 in s4)

---

### elastic__logstash-16681

**[run-1]** _(27 steps, exit_status: submitted)_
1. Six searches: `find_file "PipelineEventBusV2.java"` (renamed class — fails), `find / -name "PipelineEventBusV2.java"` (fails), `find logstash-core -name "PipelineEventBusV2.java"` (fails), `find logstash-core -name "*.java" | grep -i pipeline | grep -i bus` (finds `PipelineBusV2.java`), `find logstash-core -name "*PipelineBusV2*" -o -name "*PipelineEventBusV2*"`, and `find logstash-core -name "*PipelineBus*" -path "*/test/*"`.
2. The double-grep pipeline `find logstash-core -name "*.java" | grep -i pipeline | grep -i bus` is the key recovery: it filters all Java files for those whose names contain both "pipeline" and "bus" (case-insensitive), finding `PipelineBusV2.java` despite the `PipelineEventBusV2` naming expectation.
3. 3 edits, 6 tests — the most tests for this instance across all strategies. The s4 combined transformation (rename + structural + rewrite) makes the agent more uncertain, driving more test validation cycles.

**[run-2]** _(17 steps, exit_status: submitted)_
1. Five searches ending with `grep -n "synchronized" /home/logstash/logstash-core/src/main/java/org/logstash/plugins/pipeline/PipelineBusV2.java`. After cascading through 4 failed searches, the agent uses the inferred file path directly and greps for synchronization primitives — confirming the file's content before editing.
2. 1 edit, 4 tests. The `synchronized` grep is a content-validation step: confirming the file contains the expected synchronization patterns before making the fix.

**[run-3]** _(13 steps, exit_status: submitted)_
1. Four searches: two named-file failures, then `find logstash-core -name "*.java" | grep -i pipeline | grep -i bus` (recovery), then `find logstash-core -name "*.java" | grep -i pipeline | grep -i bus` again (same command — verifying the result).
2. 1 edit, 3 tests. 13 steps — the most efficient s4 run for this instance. The double-grep recovery works quickly.

**[run-4]** _(19 steps, exit_status: submitted)_
1. Seven searches, including `find . -name "PipelineBus*.java" -o -name "PipelineEventBus*.java"` (OR glob), `find . -name "*.java" -path "*/pipeline/PipelineBus*"`, `find . -name "AddressState.java" -path "*/pipeline/*"`, `grep -r "PipelineEventBusV2" /home/logstash --include="*.java" -l` (content search for the renamed class across all files), and a `javac` compilation check.
3. The content search `grep -r "PipelineEventBusV2" ... -l` finds all files that reference the renamed class — possibly catching usages in test files even though the implementation isn't named that.
4. 1 edit, 3 tests. The 7 searches add overhead (19 steps) but all lead to the same 1-edit fix.

**[run-5]** _(24 steps, exit_status: submitted)_
1. Five searches: named-file failures, then `find logstash-core -name "PipelineEventBus*"`, `find logstash-core -name "*.java" | grep -i pipeline | grep -i bus`, `find logstash-core -name "AddressState.java"`. The `AddressState` lookup (now with the full pipeline context established) is a s4-specific pattern.
2. 3 edits, 4 tests. More edits than R1–R4 (which all use 1 edit), suggesting R5 makes additional defensive synchronization changes.
3. **All 5 s4 runs resolve** — 5/5 consistency maintained under the combined transformation. Claude's cascading search strategy is robust enough to handle simultaneous renaming + structural reorganization.

---

### fasterxml__jackson-core-183

**[run-2]** _(50 steps, exit_status: submitted — most expensive jackson-core-183 trajectory)_
1. Two searches: `find_file "SegmentedTextBuffer.java" src` and `find_file "BufferRecycler.java" src`. Both use the renamed class name. 8 edits — the most of any jackson-core-183 run. The combined transformation (rename + structural + rewrite) requires the agent to simultaneously navigate a renamed API and a reorganized method order.
2. Many test attempts use a custom `javac` spot check pattern: `mvn compile -q && javac -cp target/classes TestReproduction.java`. The `TestReproduction.java` file is created by the agent to test a specific reproduction case, then discarded.
3. 6 tests, 50 steps. The highest-effort resolution for this instance — all the combined transformations compound: renamed class, sorted methods, new problem description all require extra orientation steps.

**[run-3]** _(29 steps, exit_status: submitted)_
1. Single search: `find_file "SegmentedTextBuffer.java"`. 6 edits, 4 tests. More efficient than R2 despite the same transformation.

**[run-4]** _(48 steps, exit_status: submitted)_
1. Six searches including `grep -n "void append|String append|char.*append" src/main/java/.../SegmentedTextBuffer.java` and `grep -n "appendChar" src/.../SegmentedTextBuffer.java`. The method-signature greps explore the renamed class's API surface: looking for `append` variants to understand the text accumulation interface.
2. Also uses `mvn compile 2>&1 | grep -E "ERROR|error" | head -30` as a targeted error-filter test. 6 edits, 5 tests, 48 steps.
3. The `append` method grep reveals a key difference: under s4, the structural sorting reorders `SegmentedTextBuffer`'s methods Z→A, placing `append`-family methods in a different position. The agent needs to search for them by content rather than relying on their original position.

**[run-5]** _(33 steps, exit_status: submitted)_
1. Two searches: `SegmentedTextBuffer.java` and `BufferRecycler.java`. 6 edits, 4 tests. Creates a `ReproduceIssue.java` file for testing. Moderate effort.
2. **Missing R1**: 4/5 under s4. R1's seed apparently cannot navigate the combined rename + structural changes to produce a correct fix.

---

### mockito__mockito-3129

**[run-1]** _(31 steps, exit_status: submitted)_
1. Four searches: `find . -name "MockUtilities.java"` (renamed from `MockUtil`), `find . -name "MockitoPlugins.java" -o -name "MockitoPluginRegistry.java"` (OR search for both possible names), `find . -name "DefaultMockitoPluginRegistry.java"`, and `ls -la | grep -E "gradle|maven|pom|build"`. The last search checks the build system — under s4's structural transformation, the project layout may have changed and the agent is verifying the build tool.
2. 6 edits, 2 tests. The OR name search `MockitoPlugins.java|MockitoPluginRegistry.java` is efficient: it finds the interface under either possible name (original or renamed) in one query.
3. 2 tests: `./gradlew compileJava` then `./gradlew compileJava compileTestJava`. Both are compile-only — the agent validates compilation but not test execution, running out of budget before the test suite.

**[run-2]** _(25 steps, exit_status: submitted — shortest s4 mockito run)_
1. Three searches: `find src -name "MockUtilities.java" -o -name "MockMaker.java"`, `find src -name "MockitoPlugins.java" -o -name "MockitoPluginRegistry.java"`, `find src -name "DefaultMockitoPluginRegistry.java"`. All use OR patterns to find either the original or renamed class.
2. 3 edits, 3 tests. Efficient — the OR search pattern reduces the number of failed lookups.

**[run-4]** _(51 steps, exit_status: submitted — most expensive s4 mockito run)_
1. Eight searches including `find_file "Plugins.java" src`, `find_file "MockitoFramework.java" src`, `find_file "MockMakers.java" src`, and `find src/test -name "*Plugin*" -o -name "*MockUtil*"`. The most comprehensive plugin-system exploration.
2. 13 edits — the highest of any mockito trajectory across all strategies. The combined transformation's renamed + reorganized plugin system requires the agent to touch 13 code locations to wire up the API correctly.
3. 6 tests including `./gradlew :test --tests "*MockitoPluginRegistry*"`. The targeted registry test validates the renamed interface contract.

**[run-5]** _(29 steps, exit_status: submitted)_
1. Six searches including `find build/reports/tests/retryTest -name "*.html"` and `find build -name "TEST-*.xml"` and `grep -A 20 "failure|error" build/test-results/retryTest/TEST-org.mockito.internal.junit.UnusedStubbingsTest.xml`. This is the only run that reads the test result XML directly (not just HTML) — parsing the failure XML to understand what the stubbing test expects.
2. 3 edits (minimal), 5 tests. The XML report reading gives the agent precise failure information, allowing a targeted 3-edit fix rather than the 13 edits needed in R4.
3. **Missing R3**: 4/5 under s4. The combined transformation causes R3's seed to fail — the renamed + reorganized plugin system creates a navigation path that leads R3 to an incorrect or incomplete fix.

---

### fasterxml__jackson-databind-1923

**[run-1]** _(32 steps, exit_status: submitted)_
1. Seven searches: `find_file "SubTypeNameValidator.java"` (correctly uses the renamed class), `find src/test -name "*.java" | grep -i subtype`, then four Spring-stub content searches: `find src/test -name "*.java" | xargs grep -l "SubTypeNameValidator|validateSubType"`, `find src/test -name "*.java" | xargs grep -l "DEFAULT_NO_DESER|IllegalType|NoDeser|defaultTyping"`, `find src/test -name "*.java" | xargs grep -l "IllegalType|security reason|nasty|1855|1599"`, and `find src/test/java/org/springframework/jacksontest/ -type f`.
2. The multiple Spring-stub content searches (using string literals like `"security reason"`, `"nasty"`, `"1855"`, `"1599"` — actual string constants from the Logstash security filter code) are highly specific. The agent is searching for the presence of known string literals that appear in the Spring Security test stubs, verifying they exist in the test directory.
3. 6 edits, 1 test. The fix adds `SubTypeNameValidator` to the illegal-types check and verifies it compiles with the Spring stubs present.

**[run-3]** _(31 steps, exit_status: submitted)_
1. Nine searches: `SubTypeNameValidator.java`, `SubTypeNameValidatorTest.java`, `TestSubTypeNameValidator.java` (trying multiple test class name forms), `search_dir "SubTypeNameValidator"` (content search), `search_dir "validateSubType"`, `search_dir "DefaultTyping"`, `find_file "BogusApplicationContext.java"`, `find_file "BogusGrantedAuthority.java"`. The `BogusGrantedAuthority` and `BogusApplicationContext` searches directly target the Spring stub files by filename — a more precise approach than R1's content search.
2. 4 edits, 2 tests. The Spring stub filename lookup is more efficient than R1's content search. R3 resolves in 31 steps with 4 edits.
3. **Why only R1 and R3 (2/5)?** The combined transformation's renaming (`SubTypeNameValidator`) is a more descriptive class name than the original `SubTypeValidator`. R1 and R3's seeds produce trajectories that correctly identify the Spring stubs via content search or filename lookup. R2, R4, R5 fail — likely because those seeds cannot locate the Spring stubs (the structural reorganization may move them to a directory that content-based search misses) or make an incorrect edit to the validator logic.

---

## Cross-Cutting Observations

**1. Cascading shell search vs single-shot SWE-agent actions:**
Claude Sonnet 4.6 uses native bash commands (`find . -name`, `grep -r`, `find | xargs grep -l`) in a cascading fallback chain. When `find_file "PipelineEventBusV2.java"` fails, Claude automatically escalates to `find / -name`, then content search, then directory traversal, then path inference. GPT-5.4's `search_dir` action doesn't support this kind of structured fallback — it either finds the term or returns empty. This explains why Claude resolves elastic__logstash-16681 5/5 in ALL strategies including s1 (where GPT-5.4 scored 0/5 for the equivalent DLQ instances).

**2. Compile-before-test is Claude's primary edit-loop:**
Almost every resolved trajectory follows: edit → `./gradlew compileJava` → `./gradlew test`. The compile step catches type errors and import mistakes early, before the slow full test suite runs. GPT-5.4 went directly to test without compilation, often discovering errors only in test output. Claude's compile-first loop produces fewer test iterations for the same fix quality.

**3. fasterxml__jackson-databind-1923 inverts between models:**
GPT-5.4 solves this 3/5 in s0 but 0/5 under structural transformation (s2). Claude fails it 0/5 in s0 but solves it under s1/s2/s4. The original problem statement is apparently sufficient for GPT-5.4 (which has specific training-data knowledge of this SubtypeValidator class) but insufficient for Claude. Transformations that either rename the class (s1/s4) or restructure the file (s2) make the fix surface clearer for Claude's shell-based exploration. This is the clearest evidence of model-specific sensitivity to problem statement framing vs code structure.

**4. google__gson-1093 fails identically for both models under renaming:**
Both Claude and GPT-5.4 score 0/5 under s1 and s4 for gson-1093. The `JsonWriter` class name is the only entry point to the fix — no method name or constant name provides an equivalent alternative anchor. When `JsonWriter` is renamed, both models' `find_file "JsonWriter.java"` fails and neither finds a recovery path. This is strong evidence that class-name anchoring is a universal failure mode, not model-specific.

**5. Test report reading — Claude's advanced debugging:**
Several Claude trajectories read Gradle/Maven test reports directly: `find build/reports/tests -name "*.html"`, `cat build/reports/...UnusedStubbingsTest.html | grep ...`, and `grep -A 20 "failure|error" build/test-results/.../TEST-...xml`. This debugging technique — reading structured test output artifacts rather than just test stdout — is never seen in GPT-5.4 trajectories and allows Claude to make targeted edits in response to specific test failures.

**6. Step economy:**
Claude uses 8–58 steps for resolved instances (median ~20). GPT-5.4 used 21–80 steps (median ~45). For the same fix on the same instance (e.g., elastic__logstash-16681), Claude uses 3–5x fewer steps. The efficiency comes from: direct `find_file` navigation (vs multi-step search), 1-edit fixes for concurrency bugs (vs GPT-5.4's 2–9 edits), and compile-before-test (fewer test iterations).

**7. elastic__logstash-14970/14981 remain hard for Claude:**
These DLQ writer instances that GPT-5.4 solved 4/5 in s0 are solved only 1/5 by Claude in s0. Both agents must understand the segment-file format (VERSION byte = 1 byte, `lastBlockId = -1` for empty segments). Claude reads the same three files (`DeadLetterQueueWriter.java`, `RecordIOReader.java`, `DeadLetterQueueWriterTest.java`) but only succeeds 1/5 — suggesting Claude's reasoning about segment binary layout is less reliable than GPT-5.4's, despite Claude's general superiority on most other instances.
