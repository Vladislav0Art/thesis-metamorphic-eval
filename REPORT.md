# Agent Trajectory Analysis Report

---------- GPT-5.4 ----------

**Setup:** 20 Java Multi-SWE-bench instances × 5 independent runs × 5 transformation strategies.
**Pass rate totals:** s0-original=7, s1-renaming=3, s2-structural=4, s3-problem-statement=7, s4-combined=3 (unique instances resolved at least once; a single instance solved across all 5 runs still counts as 1 here — use the R-column lists below for the full picture).

---


The most interesting findings:

`elastic__logstash-14970/14981` — drop from 4/5 → 0/5 under s1 because the agent hallucinates a wrong renamed class name (e.g., DeadLetterQueueFileWriter) and gets 4–6 consecutive zero-result searches before giving up.

`elastic__logstash-16681` — goes from 1/5 (s0) → 5/5 (s4). The combined rename breaks the agent's class-name search, forcing it to fall back to semantic method searches (unregisterSender, notifyAll). This produces a 9-edit comprehensive fix instead of s0's 2-edit minimal one — the transformation accidentally creates a better strategy.

`mockito__mockito-3129` — the inverse: in s0 the agent cycles through imports/edits in 4 of 5 runs (memorized-but-wrong pattern). Transformations disrupt the shortcut and force real problem-solving → improves to 4/5 under s1 and s3.

`elastic__logstash-16579` — only solvable under s3 (problem-statement only). A Java+Ruby hybrid that requires 19 searches (most of any trajectory). The original problem statement is apparently too vague to guide the agent to the right code path.

`fasterxml__jackson-databind-1923` — drops to 0/5 under s2 because the agent's path-based Spring stub discovery (-path '*org/springframework*') breaks when the test directory is restructured.


---

## === s0-original ===

**Resolved instances:** elastic__logstash-14970 (R2,R3,R4,R5), elastic__logstash-14981 (R1,R3,R4,R5), fasterxml__jackson-databind-1923 (R2,R3,R5), google__gson-1093 (R2,R3), elastic__logstash-16681 (R2), fasterxml__jackson-core-183 (R3), mockito__mockito-3129 (R4)

---

### elastic__logstash-14970

**[run-2]** _(46 steps, exit_status: submitted)_
1. The agent opens with a direct, confident class-name search: `search_dir "class DeadLetterQueueWriter" .` in step 2. It immediately gets 3 matches and opens `DeadLetterQueueWriter.java` in step 3 — no wasted exploration.
2. Root cause is quickly traced: `readTimestampOfLastEventInSegment()` computes `lastBlockId = ceil((fileSize - VERSION_SIZE) / BLOCK_SIZE) - 1`, which becomes -1 for a 1-byte file (header-only segment), causing `seekToBlock(-1)` to throw. The agent follows up with searches for `"VERSION_SIZE"` and `"VERSION ="` constants in `RecordIOReader.java` to confirm the arithmetic.
3. The fix is minimal: 5 edits total — a guard `if (lastBlockId < 0) return Optional.empty()` added before the loop in `readTimestampOfLastEventInSegment()`, plus a regression test `testOpenWithHeaderOnlySegment` added to `DeadLetterQueueWriterTest.java`.
4. The agent runs `./gradlew :logstash-core:test --tests ...DeadLetterQueueWriterTest` three times — once to confirm the test fails without the fix, then to verify the fix, then a targeted test run. This verify-fix-verify pattern shows confident, structured debugging.
5. The agent opens `RecordIOReader.java` to understand the constants but makes no edits there — it correctly identifies that only the writer's method needs the guard. Total unique files touched in edits: 2.

**[run-3]** _(42 steps, exit_status: submitted)_
1. Same opening search as R2. Adds a second search — `search_dir "DeadLetterQueueWriter" logstash-core/src/test` — to locate the test file before opening it, a slightly more cautious navigation style than R2 which opened the test by name directly.
2. Also checks Gradle task naming via `search_dir "javaTests" logstash-core` before running tests — the agent is uncertain whether to use `test` or `javaTests` task. This extra step is not present in R2.
3. Also opens `build.gradle` and `RecordIOWriter.java` (RecordIOWriter for VERSION_SIZE lookup, same as R2). 6 edits vs R2's 5 — one extra edit to insert the test method boundary cleanly.
4. Test name: `testInitializesWithHeaderOnlySegment` — slightly different wording from R2's `testOpenWithHeaderOnlySegment`. Both describe the same condition in different natural-language terms, showing stochastic variation in naming even for the same semantic concept.
5. 42 steps, slightly fewer than R2's 46, with identical outcome. The variation is in navigation style (search-first vs. open-directly) rather than fix content.

**[run-4]** _(54 steps, exit_status: submitted — longest DLQ trajectory)_
1. The same opening search, but R4 then pivots to a completely different secondary search: `search_dir "oldestSegmentTimestamp" logstash-core/src/main/java/org/logstash/common/io` — looking for a *field* rather than the VERSION_SIZE constant. This is a different mental model of the bug: approaching from the timestamp-tracking logic rather than the segment-size arithmetic.
2. Uses heavy forensic grep queries not seen in any other run: `grep -n "VERSION_SIZE\\|empty\\|segment" ...DeadLetterQueueWriterTest.java | head -80` and `grep -n -A30 -B15 "readTimestampOfLastEventInSegment" ...DeadLetterQueueWriter.java`. These context-window greps extract method bodies to avoid re-opening and paginating through large files.
3. Lists all test methods explicitly via `grep -n "@Test\\|public void test" ...DeadLetterQueueWriterTest.java` and then examines a specific existing test `testUncleanCloseOfPreviousWriter` in detail — studying test patterns before writing its own regression test.
4. 7 edits and 4 test runs (highest in this instance). Uses `./gradlew --no-daemon` and `--info` flags for more verbose diagnostic output, indicating the agent hit a test failure it needed to diagnose carefully.
5. Despite being the longest trajectory (54 steps), it reaches the correct fix. The extra steps reflect a more forensic, evidence-gathering style — this is a fundamentally different problem-solving approach from R5's direct minimalism.

**[run-5]** _(36 steps, exit_status: submitted — shortest DLQ trajectory)_
1. Only 3 searches. After the opening `"class DeadLetterQueueWriter"` search, the agent uses `search_dir "oldestSegmentPath\\|oldestSegmentTimestamp"` (like R4, looking for field names rather than constants), then just `"javaTests" .` to check task naming. No VERSION_SIZE lookup at all.
2. Only 4 edits and 2 test runs — the theoretical minimum observed for this instance. The agent goes straight to the fix without any exploratory detours into RecordIOReader or RecordIOWriter.
3. Test name: `testWriterInitializesWhenOldestSegmentContainsOnlyVersionByte` — the most descriptive test name across all 4 resolved runs. The verbose name suggests the problem statement terminology ("only version byte") was more salient in this seed's context window.
4. This is the most efficient trajectory for this instance. The contrast with R4 (54 steps) on identical code illustrates pure stochastic variance: 4 independent paths to the same fix, ranging 36–54 steps, driven entirely by the LLM sampling seed.

---

### elastic__logstash-14981

**[run-1]** _(39 steps, exit_status: submitted)_
1. Same DLQ writer class as 14970 but a slightly different manifestation. The agent's first search is identical — `search_dir "class DeadLetterQueueWriter" .` — demonstrating the same pattern anchor.
2. The agent additionally opens `RecordIOWriter.java` (not touched by 14970's run) to inspect `VERSION_SIZE` definition. This adds a few steps but shows the agent is more careful about understanding where the constant originates.
3. 6 edits are made: the guard fix in `readTimestampOfLastEventInSegment()` is similar to 14970, but the test structure is slightly different — the agent writes `testWriterInitializesWithHeaderOnlySegment` which focuses on the initialization path rather than the open path.
4. Fewer total steps (39) than 14970's run-2 (46) despite more careful constant-lookup. This suggests the run-1 seed produced a more direct exploration sequence — the agent didn't open the test file as many times (18 unique opens vs 25 for 14970).
5. Also greps `build/test-results` for `<failure` after a test run — a forensic step to understand a test failure message before making the final edit. This debugging tactic is not seen in 14970's trajectory.

**[run-3]** _(38 steps, exit_status: submitted)_
1. Only 1 search across the entire trajectory — `search_dir "class DeadLetterQueueWriter" .`. After finding the class, the agent navigates entirely by opening files directly, with no further search queries. This is the minimum search overhead of any resolved run for either DLQ instance.
2. Despite only 1 search, the agent opens 22 files (more than R1's 18) — it compensates for less searching by more file-browsing to orient itself within the codebase.
3. 4 edits, 3 tests. Test name: `testInitializeWriterWithVersionOnlySegment`. The third test run is targeted: `./gradlew ...DeadLetterQueueWriterTest.testInitializeWriterWithVersionOnlySegment` — the agent narrows to the specific test after an initial full-suite run.
4. Also opens RecordIOReader.java and RecordIOWriter.java — reads constants from both, but edits neither. 38 steps, nearly identical to R1 (39), despite the very different search strategy.

**[run-4]** _(28 steps, exit_status: submitted — shortest across both DLQ instances and all strategies)_
1. Only 1 search (`"class DeadLetterQueueWriter"`), 13 file opens, 5 edits, 2 tests. The entire trajectory from initial search to final submission fits in 28 steps — the floor for this class of problem in this dataset.
2. The agent goes: search → open implementation → open test → edit guard → edit test → run test → run targeted test → submit. Zero detours, zero failed searches, zero redundant reads.
3. Test name: `testInitializeWithVersionOnlySegment` — concise and accurate.
4. The 28-step trajectory is not "better reasoning" than R5 (57 steps) — both reach the correct fix. It is the lucky outcome of a sampling seed that happens to produce direct, confident action selection at every step, with no exploratory branching.

**[run-5]** _(57 steps, exit_status: submitted — longest for 14981, and a cautionary contrast to R4)_
1. The most search-intensive run for this instance: 5 searches. After the initial `"class DeadLetterQueueWriter"`, the agent searches for `"VERSION_SIZE"` twice (once in main, once across main+test), then `"writeByte"` in the main java path, then `"VERSION ="`. The `writeByte` search is unique to this run — the agent wants to understand HOW the version byte is physically written to infer how to detect segment emptiness.
2. 11 edits — more than double any other resolved run for this instance. Critically, several early edits target the `DROP_NEWER` storage path inside `DeadLetterQueueWriter.java` — a completely different code branch from the actual fix. The agent initially misidentifies the fix location, then self-corrects.
3. 5 test runs. After the first test failure (from the incorrect DROP_NEWER edit), the agent diagnoses and pivots to `readTimestampOfLastEventInSegment()`. The subsequent 4 test runs are all focused on the correct fix location.
4. Test name: `testOpenWithHeaderOnlySegment` — same as 14970's R2, showing the naming choices are consistent with which sub-problem the agent focuses on.
5. This trajectory is the clearest example in the entire dataset of how stochastic sampling affects not just efficiency but exploration correctness. The gap between R4 (28 steps, 1 search, correct path immediately) and R5 (57 steps, 5 searches, wrong path first) is entirely due to the random seed — the codebase is identical.

---

### fasterxml__jackson-databind-1923

**[run-2]** _(36 steps, exit_status: submitted)_
1. Agent uses `find_file "SubTypeValidator.java" src` as its first anchor — class name derived from the issue title mentioning "SubTypeValidator" and "Spring Security". Immediately opens the file.
2. A sophisticated test-infrastructure discovery step: `find src/test/java -path '*org/springframework*' -o -path '*springframework*'` reveals that there are no pre-existing Spring Security stub classes in the test tree. The agent then creates them from scratch.
3. The agent creates two stub classes: `org.springframework.security.core.GrantedAuthority` (interface) and `org.springframework.security.core.AuthorityList` (class implementing it). These are minimal stubs — not pulled from training data as correct Spring Security implementations but purpose-built for the test.
4. Fixes `SubTypeValidator.java` by adding `org.springframework.security` to the blocked-type prefixes.
5. Only 2 mvn test runs, both targeting `IllegalTypesCheckTest`. The agent's approach is surgical: create stubs, patch validator, verify. No redundant exploration.
6. The 8 edits span both creation of new stub files and modification of SubTypeValidator — a multi-file fix pattern rare in other trajectories.

**[run-3]** _(26 steps, exit_status: submitted — shortest for this instance)_
1. Starts by opening the TEST file first (`IllegalTypesCheckTest.java`) rather than the implementation — the only run for this instance that does so. This test-first navigation leads to a faster path: the agent reads the test to understand what the fix must satisfy before opening `SubTypeValidator.java`.
2. The Spring directory search (`find src/test/java/org/springframework -type f | sort`) succeeds and finds the pre-existing `BogusApplicationContext.java` stub in `src/test/java/org/springframework/jacksontest/`. Unlike R2 (which found nothing and created stubs from scratch), R3 reuses existing infrastructure.
3. 7 edits and 2 mvn test runs. Test name: `testSpringSecurityInterface`. The existing Spring stub means no new stub classes need to be created — the agent focuses entirely on the validator fix and a single new test method.
4. 26 steps vs R2's 36 — the 10-step reduction comes from reusing infrastructure rather than creating it. The test-first approach and existing stub discovery together make this the most efficient resolve for this instance.

**[run-5]** _(27 steps, exit_status: submitted)_
1. Navigation pattern matches R2 (implementation first), but uses 5 searches vs R2's 5 as well — however the search queries are slightly different: includes `find /home/jackson-databind/src/test/java/org/springframework -type f | sort` (absolute path) AND `find src/test/java/org/springframework/security -type f` (looking specifically in a `security` subdirectory that doesn't exist). The second search returns nothing — the agent then falls back to the stub it found in the first search.
2. Like R2 and R3, creates `GrantedAuthority` interface and `AuthorityList` stubs. 5 edits total (fewer than R2's 8), 3 mvn test runs.
3. Test name: `testSpringInterfaceDefaultTyping1855` — references the Jackson issue number directly, mirroring language from the problem statement.
4. R2, R3, and R5 all follow the same logical structure (find SubTypeValidator → discover/create Spring stubs → patch → test) but differ in: which file they open first, whether they reuse or create stubs, and how many Spring-directory searches they attempt. The consistent 3/5 success rate reflects this shared robust approach.

---

### google__gson-1093

**[run-2]** _(43 steps, exit_status: submitted)_
1. Minimal search footprint: only 2 `find_file` queries — `"JsonWriter.java"` then `"JsonWriterTest.java"`. The agent goes directly to the implementation without any class-hierarchy or package exploration.
2. The fix targets `JsonWriter.value(double)` at lines 486–522 — the method handling double serialization. The agent opens the file multiple times (15 total opens) to navigate different parts of a large file rather than scrolling.
3. The test added is `testLenientNonFiniteDoubles` — mirrors the exact terminology of the issue (lenient mode, non-finite doubles). The agent connects issue language to code semantics without extra search steps.
4. 8 edits, 2 mvn test runs. The second test run confirms the fix. Compact and efficient trajectory.
5. Compared to other instances, this trajectory shows the agent operating near its theoretical minimum: it knows exactly which class handles JSON writing and goes straight there. This instance is likely close to training data (Gson is a well-known library), enabling direct pattern-matching to the fix location.

**[run-3]** _(47 steps, exit_status: submitted)_
1. Uses a content-based search as the entry point: `search_dir "value(double" gson` — searching for the *method signature* rather than the class name. This is a uniquely targeted approach and finds `JsonWriter.value(double)` directly without looking up the file first.
2. Also searches for `"setLenient"` in tests and `"testLenientNonFiniteDoubles"` in src — seeking existing tests related to the lenient/non-finite theme to understand the expected behavior before writing a fix.
3. Also opens `JsonTreeWriter.java` (a different writer implementation) to compare against `JsonWriter.java`. This extra comparison step adds ~4 steps but gives the agent a richer understanding of the writer hierarchy.
4. 10 edits (vs R2's 8) and 3 mvn test runs. The maven invocation uses the full class path: `mvn -Dtest=com.google.gson.stream.JsonWriterTest test` (vs R2's shorter `-pl gson -Dtest=JsonWriterTest`). Both work.
5. The method-signature search (`"value(double"`) is the cleanest possible entry point for this bug — it pinpoints the problematic method immediately. Despite 47 steps vs R2's 43, the approach is slightly more thorough in understanding the existing test coverage.

---

### elastic__logstash-16681

**[run-2]** _(45 steps, exit_status: submitted via exit_cost)_
1. The agent correctly identifies `PipelineBusV2.java` as the target via `search_dir "class PipelineBusV2" .`. However, the trajectory shows a striking pattern: PipelineBusV2.java is opened **19 times** — the most re-reads of any single file in any trajectory. This indicates the agent repeatedly needs to revisit the concurrent code to understand state transitions.
2. The agent spends 5 search steps trying to find a `PipelineBusV2Test.java` — which does not exist (the tests are in `PipelineBusTest.java`). This dead-end wastes multiple steps.
3. Only **2 edits** are made despite 45 steps — the agent struggles to converge on the fix for a complex deadlock. One edit modifies the `AddressStateMapping` inner class, and one follows up. No tests are run at all before exit_cost.
4. The `exit_cost` exit status (cost limit reached, auto-submitted) suggests the agent exhausted its budget before it could validate or refine its fix. In the 4 other runs where this instance is not resolved, a similar pattern likely plays out with a different (wrong) fix patch submitted.
5. The low edit count combined with many file opens and 0 test runs is characteristic of a difficult concurrency bug — the agent understands the code structurally but cannot easily determine the right synchronization fix without running tests.

---

### fasterxml__jackson-core-183

**[run-3]** _(56 steps, exit_status: submitted)_
1. Minimal searching (only 2 queries): `find src -type f | grep 'TextBuffer|BufferRecycler|Test'` and `search_dir "getTextCharacters()" src/test`. The agent identifies the issue as related to `getTextBuffer()` consistency for empty buffers.
2. Opens **29 files** total — the highest file-open count across all resolved trajectories. TextBuffer.java alone is opened many times; the agent re-reads it repeatedly to navigate a large class (~600 lines) without a scroll command.
3. 10 edits to fix `getTextBuffer()` — when `_inputBuffer` is shared (the empty case), the method must return a stable representation. The agent works through multiple attempts, visible as 10 separate edit commands.
4. The regression test is named `testEmptyGetText...` and placed in `TestTextBuffer.java`. 3 mvn test runs confirm the fix converges. The multiple edits (including some that appear to roll back and retry) suggest the agent was iteratively debugging the fix.
5. This is the most complex single-class fix in the benchmark — TextBuffer has many internal state variables. The long trajectory is justified by the complexity.

---

### mockito__mockito-3129

**[run-4]** _(62 steps, exit_status: submitted via exit_cost)_
1. The highest search count in s0 (9 searches): the agent probes `"getMockMaker("`, `"getInlineMockMaker"`, interface/class declarations, and plugin-loading patterns. Mockito's plugin infrastructure spans many files, requiring extensive orientation.
2. Files touched: `MockitoPlugins.java` (interface), `DefaultMockitoFramework.java`, `Plugins.java`, `DefaultMockitoPlugins.java`, `MockitoPluginsTest.java`, `MockUtil.java`, `MockMakers.java` — 7 distinct source files, the widest blast radius of any instance.
3. 10 edits. The agent modifies the `MockitoPlugins` interface to add a `getMockMaker()` default method, then updates the framework and plugin implementations to wire it up.
4. 2 gradlew test runs. The exit_cost cutoff triggers before the agent finishes refinement, but the submitted patch is correct for run-4.
5. Runs 1–3 fail to produce a working patch. The successful run-4 submission suggests that the correct fix requires a specific sequence of interface + implementation edits that only the run-4 sampling seed happens to land on cleanly before the budget runs out.

---

## === s1-renaming ===

**Transformation:** Class names, method names, and variable names are renamed project-wide (compilation-preserving). The problem statement text may also reference the new names.

**Resolved instances:** mockito__mockito-3129 (R1,R2,R3,R4), fasterxml__jackson-databind-1923 (R5), elastic__logstash-16681 (R1,R3,R4)

**Instances that DROPPED to zero:** elastic__logstash-14970, elastic__logstash-14981 (both 4/5 in s0 → 0/5 in s1), google__gson-1093 (2/5 → 0/5), fasterxml__jackson-core-183 (1/5 → 0/5)

---

### mockito__mockito-3129

**[run-1]** _(70 steps, exit_status: submitted via exit_cost)_
1. **Renamed files present:** `MockUtil` → `MockUtils`, `MockitoPlugins` → `MockitoPluginRegistry`, `DefaultMockitoPlugins` → `MockitoDefaultPlugins`. The agent correctly adapts its initial search: `find . -name "MockUtils.java" -o -name "MockitoPluginRegistry.java"` — it uses the new names, not the old ones.
2. The renamed interface `MockitoPluginRegistry` has a name that more clearly signals its role in the plugin system. The agent navigates to it efficiently via the `find` command rather than a content search.
3. Crucially, the agent also uses method-name searches that are invariant to renaming: `grep -R "getMockMaker"` and `grep -R "getInlineMockMaker"`. These method names appear to be preserved in the renamed codebase, giving the agent stable anchors.
4. Fewer edits than s0 (7 vs 10), and only 1 test run. The clearer naming hierarchy (`MockitoPluginRegistry` for the interface, `MockitoDefaultPlugins` for the implementation) appears to reduce the cycling behavior observed in s0's runs 1–3.
5. This instance improves dramatically from 1/5 (s0) to 4/5 (s1). The renaming resolves ambiguity between `MockUtil` and `MockitoPlugins` which in s0 caused cyclic imports/edits. When the plugin-registry class has "Registry" in its name, the agent's interface vs. implementation distinction becomes cleaner.

**[run-2]** _(69 steps, exit_status: submitted via exit_cost)_
1. Files accessed match R1's set (`MockUtils.java`, `MockitoPluginRegistry.java`, `MockitoDefaultPlugins.java`) but R2 also opens `MockitoFramework.java` and `PluginRegistry.java` — exploring the broader plugin framework.
2. **13 searches** — the highest for any mockito s1 run. Includes unusual queries: `search_dir "@since 5." src/main/java` and `search_dir "version =" gradle .` — the agent is checking the project's version/API compatibility, suggesting it's concerned about which API surface to implement. This version-checking behavior is unique to R2 and reflects LLM uncertainty about which API version the test expects.
3. 8 edits, 2 test runs. Despite the extra overhead, the fix is correct. The version-checking searches are pure overhead — the fix doesn't depend on the version.
4. Follows the same overall pattern as R1 (renamed classes found correctly, method-name searches as stable anchors) but with more exploratory overhead driven by a different seed's uncertainty about API compatibility.

**[run-3]** _(66 steps, exit_status: submitted via exit_cost)_
1. Opens **49 files** — the highest file-open count for any mockito trajectory. The agent compensates for fewer searches (5 vs R2's 13) with more file browsing — essentially navigating by reading rather than searching.
2. Both `MockUtil.java` (original name) and `MockUtils.java` (renamed) appear in the accessed files — the agent reads both, showing it discovered that two similarly-named utility classes exist. This dual-read clarifies which one was renamed and which is the original.
3. 7 edits, 2 test runs. The edits follow the same pattern (interface method + implementation wiring), converging on a correct fix despite the high file-open overhead.
4. All three resolved runs (R1, R2, R3) plus R4 share the same core logic: find `MockitoPluginRegistry` interface → wire `getMockMaker()` → update `MockitoDefaultPlugins` implementation. The variation is in how much overhead (searches vs. file opens) each seed accumulates before converging.

**[run-4]** _(71 steps, exit_status: submitted via exit_cost)_
1. Searches include `search_dir "MockMakers.INLINE" src/test` — looking for how the test actually invokes the mock-maker constant. This test-driven inference of the expected API (checking what the test calls before deciding what the implementation must expose) is a clean reasoning pattern.
2. **0 test runs** despite 71 steps. The agent relies entirely on static analysis to determine correctness, which works — the submitted patch is correct.
3. 8 edits. Also opens `DefaultMockitoFrameworkTest.java` — the only s1 run to read both the plugin test AND the framework test, giving a more comprehensive view of the expected behavior.
4. All 4 resolved s1 runs exit via `exit_cost`, none via clean `submit`. The mockito problem is complex enough that the agent always exhausts budget, but the renamed class hierarchy consistently guides it to the right fix architecture.

---

### fasterxml__jackson-databind-1923

**[run-5]** _(28 steps, exit_status: submitted — SHORTEST resolved trajectory for this instance)_
1. **Renamed class:** `SubTypeValidator` → `SubtypeValidator` (lowercase 't'). The agent's first search correctly targets the new name: `find src -type f | grep -E 'SubtypeValidator|DefaultTyping|subtype|Polymorphic|Security'` — finds it immediately.
2. Unlike s0's run-2 (which had to create Spring Security stubs from scratch), this run discovers a pre-existing `org/springframework/jacksontest/BogusApplicationContext.java` file in the test tree. The agent uses this existing infrastructure rather than creating stubs, resulting in only 4 edits (vs s0's 8).
3. The trajectory is 28 steps — 8 fewer than s0's run-2. The renaming appears to have made the class hierarchy slightly cleaner to navigate.
4. Despite only being solved in 1 of 5 runs (vs s0's 3/5), this run-5 is the most efficient solve. The majority of s1 runs for this instance likely fail at the class-name inference stage or suffer from the renamed blocklist entries in SubtypeValidator making the fix location harder to identify.

---

### elastic__logstash-16681

**[run-1]** _(40 steps, exit_status: submitted via exit_cost)_
1. **Critical search confusion from renaming:** The agent's first 4 searches are `find . -name "PipelineEventBusV2.java"`, `grep -R "class PipelineEventBusV2"`, `find_file "PipelineEventBusV2.java"`, and `search_dir "PipelineEventBusV2"`. In the s1-renamed codebase, the actual class is still named `PipelineBusV2` but the problem statement apparently references a renamed form `PipelineEventBusV2`. All 4 searches return no results — 4 wasted steps.
2. The agent recovers by searching for pipeline-related files by directory: `find . (\path "*/src/main/java/*" -o -path "*/src/test/java/*") | grep "pipeline"`. This correctly reveals `PipelineBusV2.java` and the agent pivots to it.
3. The agent also opens `PipelineBus.java` (the interface) — not seen in s0's trajectory. The renaming of the problem statement causes the agent to be less certain about which class implements the bus, so it reads both the interface and the implementation.
4. Only 1 edit (vs s0's 2), and 2 test runs. Despite the initial search confusion costing 4 steps, the agent still produces a working fix. This explains the improvement from 1/5 → 3/5: the renaming causes confusion but not catastrophic failure; in 3 of 5 runs the agent recovers in time.

**[run-3]** _(42 steps, exit_status: submitted via exit_cost)_
1. Same initial confusion as R1: `search_dir "class PipelineEventBusV2"` and `search_dir "PipelineEventBusV2"` both return nothing. The fallback this time is a wildcard find: `find . -iname '*PipelineEventBus*' -o -iname '*PipelineBus*'` — which succeeds, locating `PipelineBusV2.java`.
2. A unique search not seen in other runs: `search_dir "multipleSendersPreventPrune"` — a specific test method name. The agent is looking for the deadlock regression test by its method name, possibly because the rewritten problem statement (in s1 combined with s3 on s4, but here the s1 problem statement alone) references the test scenario by this name. Finding it confirms the test infrastructure location.
3. 5 edits — more than R1's 1 edit, but 0 test runs. The agent makes multiple edits to synchronization logic but doesn't validate them before budget exhaustion.
4. The larger edit count without tests suggests the agent understood the fix (synchronization block changes) but ran out of budget before test validation — a different failure mode from R1's early recovery.

**[run-4]** _(45 steps, exit_status: submitted via exit_cost)_
1. Same failed searches `"class PipelineEventBusV2"` → `"PipelineEventBusV2"` → `"PipelineEventBus"`. The third search (`"PipelineEventBus"` without the V2 suffix) is a breadth-first fallback — searching for the base name rather than the versioned one.
2. The agent opens `PipelineBus.java` (the interface, not the implementation) — same behavior as R1. The renamed problem statement causes uncertainty about which class to target, leading the agent to read the interface definition first.
3. Only 2 edits (same as R1) and 0 test runs. The agent's fix attempt is minimal — it edits the implementation after reading the interface but does not run tests to verify.
4. Exits at cost limit with a partially correct patch. The 3 failed initial searches waste approximately 6 steps (about 13% of the budget).

**Cross-strategy insight (why elastic__logstash-14970/14981 drop to 0/5 under s1):** These two DLQ instances rely on the agent's ability to search for `"class DeadLetterQueueWriter"` as the entry point. Under s1, the class is renamed (e.g., to something with "File" suffix or different casing). Exploration of a failed s1 run for elastic__logstash-14970 showed the agent searching for `"DeadLetterQueueFileWriter"` — a non-existent name hallucinated from the renamed problem statement. With 4–6 consecutive zero-result searches, the agent never reaches the right file. The DLQ instances are particularly vulnerable because (unlike logstash-16681) there is no interface/directory fallback path — the fix is entirely within one class that can only be found by name.

---

## === s2-structural ===

**Transformation:** Methods in the changed files are sorted Z→A within each class; some files may be relocated to different package directories. No identifier renaming.

**Resolved instances:** elastic__logstash-14970 (R1,R2,R3,R4,R5), elastic__logstash-14981 (R1,R2,R3,R4,R5), elastic__logstash-16681 (R2,R4,R5), mockito__mockito-3129 (R1,R3)

**Notable improvements over s0:** elastic__logstash-14970 (4/5 → 5/5), elastic__logstash-14981 (4/5 → 5/5), elastic__logstash-16681 (1/5 → 3/5)

**Instances that DROPPED to zero:** fasterxml__jackson-databind-1923 (3/5 → 0/5), google__gson-1093 (2/5 → 0/5), fasterxml__jackson-core-183 (1/5 → 0/5)

---

### elastic__logstash-14970

**[run-1]** _(46 steps, exit_status: submitted)_
1. Essentially the same trajectory as s0. First action: `search_dir "class DeadLetterQueueWriter" .` — succeeds because structural transformation doesn't change class names. The agent reaches the implementation in the same number of steps.
2. A notable difference: the agent's second search is `search_dir "EMPTY_DLQ" logstash-core/src/test/java` (vs s0's `"VERSION_SIZE"`). In the s2-sorted codebase, the constant `EMPTY_DLQ` (or a similar test-related constant) is more prominent due to method ordering — the agent latches onto a different landmark in the test file.
3. 6 edits (vs s0's 5), 3 test runs. The fix is identical in nature: guard `lastBlockId < 0` and add a regression test `testInitializeWithHeaderOnlySegment`.
4. This instance is now solved in ALL 5 runs (vs 4/5 in s0). The structural transformation may have slightly improved the determinism of the fix path: with methods sorted alphabetically, `readTimestampOfLastEventInSegment` appears in a more predictable position in the sorted file, and the agent's file-navigation (line-number based `open`) doesn't need to search for the right line range.

**[run-2]** _(55 steps, exit_status: submitted)_
1. Same entry search `"class DeadLetterQueueWriter"` then immediately targets the test file with `search_dir "VERSION_SIZE" logstash-core/src/test/java/org/logstash/common/io`. This pattern — implementation first, then test constant — is consistent with s2 R1.
2. 7 edits and 5 test runs — the highest test count for this instance across any strategy/run. The agent validates intermediate states aggressively: each edit to the guard condition and each new test method is followed by a `./gradlew :logstash-core:test` call.
3. Steps (55) are higher than R1 (46) because of the additional test cycles, but all 5 test runs pass progressively — the agent is iterating toward a correct solution rather than spiraling.
4. Structurally equivalent to R1 in approach; higher step count is purely from more thorough test validation.

**[run-3]** _(43 steps, exit_status: submitted — 7% fewer steps than R1)_
1. 4 searches including `search_dir "readTimestampOfLastEventInSegment" logstash-core/src/test/java` — the agent searches for the buggy method name directly in the test file, rather than searching for constants. This is the most method-focused search strategy seen for this instance.
2. A secondary search for `VERSION_SIZE` in `src/main/java` (not `src/test/java` as in R1/R2) shows the agent checking the constant's definition rather than its test usage.
3. Only 4 edits and 2 test runs — the fastest clean run for this instance under s2, suggesting the direct method-name search finds the right context with minimal exploration overhead.
4. Confirms the 5/5 consistency of s2 for this instance: even the most minimal search approach succeeds because class names are unchanged.

**[run-4]** _(49 steps, exit_status: submitted)_
1. Different entry point: `find_file "DeadLetterQueueWriter.java"` then `find_file "DeadLetterQueueWriterTest.java"`. R4 is the only run that uses `find_file` (filename-based) rather than `search_dir` (content-based) as the first action.
2. A unique secondary search: `search_dir "oldestSegmentPath" logstash-core/src/main/java/org/logstash/common/io`. The agent is exploring segment lifecycle methods beyond just the header-reading function — a broader understanding of the DLQ segment management API.
3. 6 edits and 5 test runs (matching R2 in test count). Multiple validation cycles again: the wider exploration of `oldestSegmentPath` leads to extra edits that require testing.
4. Despite the more exploratory approach, the fix is correct. The structural transformation doesn't disrupt filename-based discovery.

**[run-5]** _(39 steps, exit_status: submitted — fewest steps of all s2 runs for this instance)_
1. Entry search `search_dir "class DeadLetterQueueWriter"` then `search_dir "oldestSegmentTimestamp\|oldestSegmentPath"` — using regex alternation to search for two related methods simultaneously. This multi-target search is the most efficient search pattern seen: 3 searches total cover all needed context.
2. Only 4 edits and 3 test runs. The alternation search provides enough context that the agent makes fewer exploratory edits and tests only the final state.
3. At 39 steps, this matches s3 R3's 21 steps as a near-minimal trajectory — but with more tests validating the fix.
4. R5 exemplifies the "tail-end efficiency" pattern: later seeds occasionally land on particularly direct exploration paths.

---

### elastic__logstash-14981

**[run-1]** _(29 steps, exit_status: submitted — FASTEST trajectory for this instance across all strategies)_
1. Only 2 searches: `find_file "DeadLetterQueueWriter.java" .` and `search_dir "DeadLetterQueueWriter" logstash-core/src/test`. Minimal overhead — the agent goes straight to the implementation and test.
2. Only 2 edits total — the most surgical fix seen for this instance: one edit to the guard in `readTimestampOfLastEventInSegment()` and one test addition. No exploratory detours into RecordIOWriter or RecordIOReader.
3. The method sorting in s2 may have paradoxically made the fix location easier to predict. If `readTimestampOfLastEventInSegment` falls at a predictable sorted position, the agent needs fewer re-reads to stay oriented, reducing step count from 39 (s0 run-1) to 29 (s2 run-1).
4. Improves from 4/5 (s0) to 5/5 (s2). The structural transformation appears to stabilize this instance without disrupting it.

**[run-2]** _(33 steps, exit_status: submitted — fastest clean s2 run for this instance)_
1. Two searches only: `search_dir "DeadLetterQueueWriter" logstash-core` and `search_dir "VERSION_SIZE" logstash-core/src/main/java/org/logstash/common/io`. The second search targets the constant definition rather than its test usage — opposite of R1's approach, equally effective.
2. 4 edits and 3 test runs. The agent gets to the fix faster (33 vs R1's 29 which is the overall fastest, but R2 is close) by finding the constant definition and reasoning backward to the write-path bug.
3. Compact trajectory: fewer open-file cycles than R1 (7 files vs R1's implied files). The structural transformation's method sorting makes the relevant methods appear together in the sorted file, reducing navigation overhead.
4. Confirms that s2's 5/5 consistency is robust across very different search strategies: whether the agent starts with `find_file` (R1) or `search_dir` (R2), it reaches the right location.

**[run-3]** _(51 steps, exit_status: submitted)_
1. Six searches — more exploration than R1/R2. Agent tries `search_dir "updateOldestSegmentReference()" logstash-core/src/main/java` (searching for a method it expects to exist based on context) and `search_dir "oldestSegmentTimestamp" logstash-core/src/main/java/org/logstash/common/io`. These suggest the rewritten problem statement (s3 changes code only; s2 changes structure only) or training priors lead the agent to look for segment reference updating.
2. 7 edits and 6 test runs — the highest combined count for this instance across any run. The extra searches lead to a more thorough understanding but also more iterations.
3. Agent also searches `search_dir "write.*VERSION"` and `search_dir "javaTests"` — the latter confirming the Gradle test task name. The exploration overhead does not prevent a correct fix.
4. R3 is the "heavy" run — more effort, same result. The structural transformation doesn't limit success but doesn't prevent over-exploration either.

**[run-4]** _(52 steps, exit_status: submitted)_
1. Searches include `search_dir "1.log" logstash-core/src/test` — a very specific test fixture filename. The agent is looking for test data files that represent single-byte DLQ segments, which directly relates to the bug condition (1-byte segment causing `lastBlockId = -1`). This is the only run across any strategy that searches for test fixture files by name.
2. Also searches `search_dir "isOldestSegmentExpired"` — another segment lifecycle method. The agent is building a broader model of the DLQ segment API before making its fix.
3. 5 edits and 3 test runs. The test fixture search pays off: the agent writes a regression test that creates a 1-byte segment file and verifies the guard handles it, closely matching the bug's root cause.
4. The `1.log` fixture search is evidence that the structural transformation (by moving methods around) caused the agent to read more of the class, discovering the test data loading pattern that informed a more precise regression test.

**[run-5]** _(48 steps, exit_status: submitted)_
1. Minimal search: `search_dir "class DeadLetterQueueWriter" logstash-core` and `search_dir "oldestSegmentTimestamp\|oldestSegmentPath"`. Same alternation-search pattern as elastic__logstash-14970 R5.
2. 4 edits and 4 test runs. The agent validates the fix thoroughly without over-exploring.
3. A cross-instance pattern is emerging: the alternation search `"oldestSegmentTimestamp\|oldestSegmentPath"` appears in both 14970 R5 and 14981 R5, suggesting the same seed (run-5) tends toward regex-alternation searches, which are more efficient.
4. All 5 runs succeed under s2 for this instance, confirming the 5/5 outcome is stable across diverse strategies.

---

### elastic__logstash-16681

**[run-2]** _(46 steps, exit_status: submitted via exit_cost)_
1. More direct search strategy than s0: `find_file "PipelineBusV2.java"` (vs s0's `search_dir "class PipelineBusV2"`). The agent goes straight for the filename rather than class declaration.
2. PipelineBusV2.java is opened 21 times (vs s0's 19) — even more re-reads, consistent with the difficulty of the concurrency bug.
3. 3 edits (vs s0's 2), 0 test runs. Still exits via cost limit. The structural changes (method sorting) don't change the synchronization fix required, but the agent spends slightly more time re-navigating the sorted file.
4. Improves from 1/5 → 3/5 overall. This improvement likely comes from the sorted method ordering making the `unregisterSender` / `blockOnUnlisten` methods easier to locate consistently across seeds.

**[run-4]** _(45 steps, exit_status: submitted via exit_cost)_
1. Search pattern: `search_dir "class PipelineBusV2"`, then `search_dir "PipelineBusV2" logstash-core/src/test`, then `search_dir "class AddressState" logstash-core/src/main/java/org/logstash/plugins/pipeline`. The third search — for the inner `AddressState` class — is new; the agent is exploring the data structure that tracks pipeline address lifecycle, which is key to understanding the deadlock.
2. 8 edits — the most of any s2 run for this instance (vs R2's 3). The agent makes more synchronization changes: adding guards in both `registerSender` and `unregisterSender` paths, not just one.
3. 0 test runs before budget exhaustion. Despite the larger edit count, the patch is correct. The `AddressState` search gave the agent enough context to make a comprehensive fix without test iteration.
4. R4's comprehensive fix (8 edits) contrasts with R2's minimal fix (3 edits). Both succeed, but via very different trajectories — reflecting the randomness in which synchronization paths the agent decides to guard.

**[run-5]** _(34 steps, exit_status: submitted — only clean submission for this instance under s2)_
1. Six searches, including unique ones: `search_dir "addressStates.mutate"` (searching for the mutation pattern on the thread-safe address map), `grep -n "class AddressState|assign|input"`, and `grep -n "UncaughtException|AtomicReference|join(Duration|isAlive()"`. The last grep searches for concurrency primitives — `AtomicReference`, `join(Duration`, `isAlive()` — in one query.
2. The multi-primitive grep demonstrates sophisticated understanding of Java concurrency: the agent is looking for the join/wait pattern that causes the deadlock by scanning for all relevant synchronization constructs simultaneously.
3. 4 edits and 4 test runs — the only s2 run for this instance that fully validates its fix. This explains why R5 is a clean submission while R2 and R4 exit at cost.
4. The `addressStates.mutate` search is the earliest-seen evidence of the agent understanding that the deadlock occurs during address state mutation — a more precise diagnosis than simply searching for `unregisterSender`.

---

### mockito__mockito-3129

**[run-1]** _(71 steps, exit_status: submitted via exit_cost)_
1. **File has moved:** `MockitoPlugins.java` is located in `plugins/api/` subdirectory rather than `plugins/` in the original. The agent must use content-based search to find it: `search_dir "interface MockitoPlugins"` — it cannot rely on knowing the exact path.
2. The agent makes **21 edits** — the highest edit count across all resolved trajectories. Despite the correct overall approach (wiring `getMockMaker()` through the interface), the agent cycles through import statements and method signatures multiple times.
3. Despite the high edit count, the fix is correct in R1 and R3. The file relocation forces the agent to reason about the plugin system from interface discovery rather than path knowledge, which appears to produce a more thorough (if longer) exploration.
4. 4 test runs validate intermediate and final states. The additional test runs (vs s0's 2) reflect the extra uncertainty introduced by the moved file.

**[run-3]** _(41 steps, exit_status: submitted)_
1. First action: `find src subprojects -type f | grep -E 'MockUtil|MockitoPlugins|MockMaker'` — a combined `find` + `grep` pipeline searching for all three relevant class names in one command. This multi-target file discovery is more efficient than searching for them individually.
2. Searches also include `search_dir "getInlineMockMaker" src/test src/main` and `grep -R "implements MockitoPlugins"` — method and interface implementation searches that are stable regardless of file location.
3. 7 edits and 3 test runs. Fewer edits than R1 (21) — the multi-target initial search provides enough context that the agent doesn't need to cycle through as many edit-revert loops.
4. The `find + grep` pipeline approach is characteristic of runs that succeed quickly under s2: path-agnostic content search bypasses the file-relocation confusion entirely. Both R1 and R3 succeed; R3 does so more efficiently.

**Cross-strategy insight (why jackson-databind-1923 drops to 0/5 under s2):** The s2 structural transformation reorganizes the test package hierarchy. In s0, the agent uses `find src/test/java -path '*org/springframework*'` to discover (or not discover) existing Spring Security test stubs — a path-based search that depends on directory structure. Under s2, the Spring Security stubs or the test directory structure are reorganized, causing this search to fail. Without the infrastructure discovery step, the agent tries to create Spring stubs without understanding the existing test imports, producing an incomplete fix. This path-dependency is fragile under structural reorganization.

---

## === s3-problem-statement ===

**Transformation:** Only the problem statement text is rewritten — code is identical to s0. The issue description is reformulated, potentially with different terminology, additional context, or different emphasis.

**Resolved instances:** elastic__logstash-14970 (R1,R2,R3,R4,R5), elastic__logstash-14981 (R1,R2,R3,R4,R5), google__gson-1093 (R1,R3), elastic__logstash-16681 (R1), fasterxml__jackson-core-183 (R2), mockito__mockito-3129 (R2,R3,R4,R5), elastic__logstash-16579 (R2)

**Notable improvements:** elastic__logstash-14970 (4/5 → 5/5), elastic__logstash-14981 (4/5 → 5/5), mockito__mockito-3129 (1/5 → 4/5), elastic__logstash-16681 properly submitted (R1), elastic__logstash-16579 unlocked from 0/5 → 1/5.

---

### elastic__logstash-14970

**[run-1]** _(39 steps, exit_status: submitted — 15% fewer steps than s0's 46)_
1. Same entry search `"class DeadLetterQueueWriter"` (code is unchanged), but the agent's second and only other search is `search_dir "javaTests" .` — it's checking Gradle task naming to run tests correctly. This extra care suggests the problem statement rewrite provided explicit guidance about the test harness to use.
2. 7 edits (vs s0's 5) — the agent writes a slightly more comprehensive test, naming it `testInitializeWithVersionOnlySegment`, mirroring the rewritten problem statement's language ("version-only segment" instead of "header-only segment").
3. The terminology from the rewritten problem statement directly shapes the test name the agent writes — showing how problem framing propagates into agent decisions at the code level.
4. Achieves 5/5 consistency (up from 4/5). The rewrite appears to resolve the ambiguity that caused one s0 run to fail.

**[run-2]** _(43 steps, exit_status: submitted)_
1. Two searches: `search_dir "class DeadLetterQueueWriter" logstash-core` and `search_dir "VERSION =" logstash-core/src/main/java/org/logstash/common/io`. The second search targets the constant declaration `VERSION =` (not `VERSION_SIZE` as seen in most runs) — a slight variation that reaches the same location via the constant's assignment rather than its derived size.
2. 4 edits and 4 test runs. The agent validates the fix at each iteration: initial guard addition, test stub, test body, and final verification.
3. A unique test validation step: `./gradlew :logstash-core:compileTestJava` before the main test run — checking compilation separately before executing. This compile-first pattern doesn't appear in other runs and suggests the rewritten problem statement mentioned compilation as a validation step.
4. Trajectory is similar to R1 in structure but uses different constant search terms, showing how slight problem-statement phrasing variations translate to different but equivalent search queries.

**[run-3]** _(21 steps, exit_status: submitted — SHORTEST trajectory for this instance across all strategies and all runs)_
1. Two searches only: `find_file "DeadLetterQueueWriter.java"` and `search_dir "class DeadLetterQueueWriterTest" logstash-core/src`. Only 5 files opened. The agent goes directly to the implementation and test class with no exploratory detours.
2. 4 edits and 2 test runs. Both tests pass. At 21 steps, this is by far the most efficient resolution of this instance — less than half the steps of s0's representative run (46 steps) and a third fewer than s2's fastest (R2 at 29 steps for elastic__logstash-14981).
3. The combination of minimal search, minimal file reads, and direct fix suggests R3's seed produces a sampling trajectory where the model confidently identifies the bug location from the first file it reads, needing only one correction + one test cycle.
4. This trajectory demonstrates the upper bound of efficiency for this bug: 21 steps is likely near-optimal given the required read → fix → test cycle.

**[run-4]** _(49 steps, exit_status: submitted)_
1. Three searches: `search_dir "class DeadLetterQueueWriter"`, `search_dir "VERSION_SIZE" logstash-core/src/main/java`, and `search_dir "javaTests" logstash-core`. The third search — finding the Gradle task name — indicates the rewritten problem statement gave a hint about the test task name used in this project.
2. 6 edits and 6 test runs — highest test count across all s3 runs for this instance. The agent iterates through multiple guard condition forms before settling on the correct one.
3. The repeated test runs (6) despite correct fixes on earlier iterations suggests the agent saw intermediate test failures (perhaps from the test method not yet being written) and looped back to add test coverage before submitting.
4. The `javaTests` task search is a specific tell: the rewritten problem statement likely mentioned the Gradle test task explicitly, and the agent is confirming it exists before running tests.

**[run-5]** _(40 steps, exit_status: submitted)_
1. Three searches with the regex alternation: `search_dir "VERSION_SIZE\\|BLOCK_SIZE\\|seekToBlock\\|seekToOffset" logstash-core/src/main/java`. This 4-way alternation is the most complex regex search in the entire dataset — the agent is looking for 4 related constants/methods simultaneously, mapping the full context of the DLQ segment reading code.
2. 10 edits (highest for this instance under s3) and 4 test runs. The comprehensive context gathered by the 4-way search leads to a more thorough fix — the agent edits multiple related methods, not just the `readTimestampOfLastEventInSegment` guard.
3. 13 files opened — the most of any run for this instance. The broader search context induces broader code reading, which leads to a more complete understanding of the fix surface.
4. R5 represents the "maximum effort" case for this instance: the 4-way alternation search finds far more context than needed, leading to extra edits. The fix is still correct — the additional edits address related edge cases rather than introducing bugs.

---

### elastic__logstash-14981

**[run-1]** _(47 steps, exit_status: submitted)_
1. **Different exploration order vs s0:** The agent opens `DeadLetterQueueWriterTest.java` FIRST (before the implementation). This test-first approach is unusual and suggests the problem statement rewrite framed the issue in terms of expected test behavior rather than implementation bugs.
2. The agent introduces a constant `EMPTY_DLQ = VERSION_SIZE` directly in the test class — adopting problem-statement terminology. This constant is not in the original test code but the rewritten problem statement apparently uses this term.
3. 8 edits and 4 test runs (most test runs for this instance across any strategy). The extra test runs suggest the agent is more uncertain about the fix — the test-first approach forces it to validate more iterations.
4. More steps (47) than s2's fastest run (29) but similar to s0 (39). The problem-statement rewrite makes the agent more test-focused but doesn't reduce complexity.

**[run-2]** _(39 steps, exit_status: submitted)_
1. Two searches: `search_dir "class DeadLetterQueueWriter"` and `search_dir "oldestSegmentPath\\|oldestSegmentTimestamp"`. The alternation search for segment reference fields is the same pattern seen in s2 R5 for elastic__logstash-14970 — again the run-2 seed appears to favor regex alternation searches.
2. 6 edits and 5 test runs. The `oldestSegmentPath` search leads the agent to include segment path management in its fix context, similar to s2's R4/R5. This results in more edits but ensures the fix is comprehensive.
3. The agent adopts a similar test-first exploration style as R1 (opening the test file early) but arrives at a slightly more implementation-focused fix based on the `oldestSegmentPath` search.
4. Efficient overall: 39 steps is near the median for this instance. The 5 test runs are more than typical but all pass sequentially.

**[run-3]** _(29 steps, exit_status: submitted — TIED with s2 R1 for the fastest clean run)_
1. Only 2 searches: `search_dir "class DeadLetterQueueWriter"` and `search_dir "oldestSegmentTimestamp\|oldestSegmentPath"`. Same minimal two-search pattern as R2, but R3 needs fewer steps overall.
2. 4 edits and 4 test runs in only 29 steps — the agent is highly efficient, making exactly one edit per test cycle. The problem-statement rewrite appears to provide enough context that R3's seed finds the correct fix on the first substantive edit.
3. The `oldestSegmentTimestamp|oldestSegmentPath` alternation pattern now appears in s3 R2, R3, and s2 R5 for elastic__logstash-14981 — suggesting this is a particularly effective search for this instance, regardless of the random seed.
4. At 29 steps, this matches s2's fastest run for this instance, confirming that the problem-statement rewrite doesn't add overhead once the agent settles on the right search strategy.

**[run-4]** _(53 steps, exit_status: submitted)_
1. Six searches — the most exploratory run under s3 for this instance. Includes `search_dir "updateOldestSegmentReference()"` and `search_dir "writeVersion" logstash-core/src/main/java/org/logstash/common/io`. The `writeVersion` method search indicates the agent is tracing how the VERSION byte is written during segment initialization, working backward from the write side to understand the read-side bug.
2. 11 edits and 5 test runs — most edits of any run for this instance across all strategies. The deep tracing of `writeVersion` leads the agent to make additional defensive edits in the write path, not just the read path.
3. The agent runs `./gradlew test --tests org.logstash.common.io.DeadLetterQueueWriterTest` (without the `:logstash-core:` project qualifier) early on — a failing command that suggests the agent learned the correct Gradle command structure mid-trajectory.
4. Despite the highest edit count (11), all test runs eventually pass. R4 demonstrates that even highly exploratory trajectories reach correct fixes when the problem statement provides rich context.

**[run-5]** _(52 steps, exit_status: submitted)_
1. Four searches including `search_dir "updateOldestSegmentReference()" logstash-core/src/main/java` and `search_dir "static final byte VERSION"`. The `updateOldestSegmentReference()` search (also seen in R4 and s2 R3) targets a specific helper method that manages segment reference counting — the agent believes this method is involved in the bug.
2. 8 edits and 3 test runs. Slightly heavier than R3 but lighter than R4. The `static final byte VERSION` search finds the version constant's declaration site, giving the agent the full context for how versions are encoded.
3. 10 files opened — above average for this instance. The broader file exploration is consistent with the agent mapping the full DLQ segment lifecycle before committing to a fix.
4. R5 for this instance under s3 follows the R4 pattern (deep exploration, many edits) but is slightly more efficient. The five-run sweep under s3 shows the full range: from 29 steps (R3) to 53 steps (R4), with all runs resolving correctly.

---

### google__gson-1093

**[run-1]** _(43 steps, exit_status: submitted)_
1. Same minimal search footprint as s0: `find_file "JsonWriter.java"` and `find_file "JsonWriterTest.java"`. The code is unchanged, so navigation is identical.
2. 9 edits (vs s0's 8) and 3 test runs (vs s0's 2). Slightly more testing effort, consistent with a more test-focused problem description.
3. Overall behavior is very similar to s0 — the problem-statement rewrite doesn't significantly change how the agent tackles this well-understood class.

**[run-3]** _(37 steps, exit_status: submitted)_
1. Same minimal search pattern: `find_file "JsonWriter.java"` and `find_file "JsonWriterTest.java" gson/src/test`. Identical to R1's entry path — the code is unchanged under s3, so `find_file` always succeeds immediately.
2. 8 edits and 2 test runs (`mvn -pl gson -Dtest=JsonWriterTest test` × 2). Fewer steps than R1 (43 vs 37) with the same edit count — R3 reaches the fix solution faster after reading the file.
3. The fix content is equivalent to R1: modifying the `value(double)` method's format string or adding a special-case for integer-valued doubles. The two test runs validate before and after the fix.
4. R1 and R3 solve this instance under s3 (2/5 matching s0's 2/5). R3's slightly shorter trajectory (37 vs 43 steps) reflects a seed that more immediately targets the relevant method after opening `JsonWriter.java`. The 0/5 failure runs (R2, R4, R5) show the agent's instability on this instance — even with the same code and a helpful problem statement, 3 of 5 seeds fail to produce a correct fix.

---

### elastic__logstash-16681

**[run-1]** _(40 steps, exit_status: submitted — the ONLY clean submission for this instance across all strategies)_
1. This is the most significant finding for this instance: s3's run-1 is the only trajectory across all 5 strategies that exits via `submitted` (not `exit_cost`). The agent runs **3 tests** (vs 0 for s0/s2) and validates its fix before submitting.
2. Fewer files opened (12 vs s0's 19) — the problem-statement rewrite evidently directs the agent more precisely. One of the 3 searches targets `"class Testable extends PipelineBusV2"` — the agent knows to look for the test subclass that exercises the deadlock scenario, which it could only know from the rewritten problem statement context.
3. 3 edits (vs s0's 2) include adding a regression test `v2DoesNotDeadlockWhenAddressMutationNotifiesWhileBlockingUnlistenHoldsListenerLock` — a test with a highly specific name encoding the exact deadlock condition. The agent derived this test name from the problem statement framing.
4. This instance is solved only in R1 (1/5 runs, same rate as s0). Despite the trajectory quality being the best across all strategies, the fix still requires exact concurrency reasoning and doesn't generalise to other seeds.

---

### fasterxml__jackson-core-183

**[run-2]** _(57 steps, exit_status: submitted)_
1. More search effort than s0 (5 searches vs 2): the agent tries multiple variants of `find_file "TextBufferTest.java"` before finding the test file named `TestTextBuffer.java`. The rewritten problem statement may use different terminology that slightly misdirects the test-file search.
2. Files opened (22) and edits (9) are similar to s0 (29 opens, 10 edits). The fix is the same `getTextBuffer()` consistency repair.
3. 3 test runs. The trajectory length (57 steps vs 56) is virtually identical to s0.

---

### mockito__mockito-3129

**[run-2]** _(72 steps, exit_status: submitted via exit_cost)_
1. The agent opens **45 files** — the highest file-open count of any trajectory in this entire analysis. This indicates extensive framework exploration driven by a more detailed problem description that references many interfaces and classes.
2. 8 edits and **0 test runs**. Despite no test validation, the submitted patch is correct in runs 2–5. The problem-statement rewrite appears to provide enough implementation context that the agent can reason about correctness statically.
3. Searches include `"getMockMaker"`, `grep -R "implements MockitoPlugins"`, `"getPlugins()"` — method-centric queries that search for the correct integration points regardless of file layout.
4. Improves dramatically from 1/5 (s0) to 4/5 (s3). The rewritten problem statement apparently clarifies the API contract that `getMockMaker()` must satisfy, allowing the agent to make the correct interface + implementation changes consistently.

**[run-3]** _(72 steps, exit_status: submitted)_
1. Six searches, including two searches for `"MockitoPlugins"` at different scope levels: first `search_dir "MockitoPlugins" src/test test-subprojects .` (broad scope across multiple directories) and then `search_dir "MockitoPlugins" .` (repo-wide). The repeated search with expanding scope suggests the first result set was insufficient and the agent re-queried to find all occurrences.
2. Also searches `search_dir "implements MockitoPlugins" src` and `search_dir "implements MockitoPlugins" .` — again duplicated with expanding scope. This is a less efficient search pattern than R2's single-pass exploration.
3. 13 edits and 3 test runs. The high edit count (vs R2's 8) reflects more cycling through interface definition changes. Three test runs validate intermediate and final states.
4. Despite the less efficient search strategy, the fix is correct. R3's 72 steps (matching R2's 72) suggests this is a naturally step-heavy instance regardless of seed, and the problem-statement rewrite provides enough context for both seeds to converge on the correct solution.

**[run-4]** _(78 steps, exit_status: submitted via exit_cost)_
1. Eleven searches — by far the most search-heavy trajectory for this instance. Searches include `search_dir "class MockUtil"`, `search_dir "interface MockitoLogger"`, and multiple repeated searches for `"getInlineMockMaker()"` with narrowing scope. The agent is building a comprehensive map of the Mockito plugin system.
2. The `interface MockitoLogger` search is unique — the agent is exploring whether `getMockMaker` belongs to the logging interface or the plugins interface, indicating uncertainty about the API surface. This uncertainty is eventually resolved correctly.
3. 10 edits and 0 test runs. Budget exhausted before test validation, but the submitted patch is correct. The extensive search phase consumes budget that would otherwise go to tests.
4. R4's pattern — many searches, many edits, no tests, correct patch — is different from R2 and R3 (which both ran 3 tests). This divergence between runs that test and runs that don't, yet both succeed, shows that the problem-statement rewrite provides enough context for the agent to reason about correctness statically.

**[run-5]** _(72 steps, exit_status: submitted via exit_cost)_
1. Twelve searches — one more than R4 and the highest count in the s3 mockito trajectories. Includes `find_file "MockMakers.java" src/main/java` — searching for a factory class that may aggregate mock maker implementations. This `MockMakers` factory search doesn't appear in R2–R4.
2. Multiple searches for `"getInlineMockMaker"` at different scopes (7 variants across R4 and R5), reflecting the agent's effort to map every location where `getInlineMockMaker` is called or defined.
3. 9 edits and 0 test runs. Same pattern as R4: extensive search, many edits, no tests, correct submission.
4. R4 and R5 share the "no-test, exit_cost, correct" pattern while R2 and R3 share the "3-test, submitted" pattern. The two behavioral clusters within s3 mockito suggest two distinct exploration strategies that both produce correct results — the problem-statement rewrite is permissive enough to support multiple valid approaches.

---

### elastic__logstash-16579

**[run-2]** _(57 steps, exit_status: submitted via exit_cost — the ONLY resolved run for this instance across all strategies)_
1. This is a hybrid Java + Ruby codebase: `BufferedTokenizerExt.java` (Java implementation) with `buftok_spec.rb` (Ruby test specs). The agent makes 7 edits spanning both files — the only instance requiring cross-language edits.
2. The agent performs **19 searches** — by far the most of any trajectory in this analysis. It searches for `"BufferedTokenizer"`, `"input buffer full"`, `"FileWatch::BufferedTokenizer.new"`, `"BufferedTokenizer.new("`, and more. This extreme search density reflects genuine difficulty finding the relevant code in an unfamiliar Ruby/Java hybrid structure.
3. The rewritten problem statement (s3) appears to be the only version that gives the agent enough context to attempt this fix at all. In s0, s1, s2, and s4, this instance produces zero resolved runs — the original problem statement may be too vague about the buffer overflow behavior to guide the agent to the right code path.
4. 2 test runs via `./gradlew :logstash-core:rubyTests` (running Ruby specs from the Java test harness) and `compileJava`. The mixed-language test setup adds complexity.
5. The instance is solved via exit_cost auto-submission, meaning the agent hit its budget limit — but the submitted patch happened to be correct. This is the most serendipitous resolution in the dataset.

---

## === s4-combined ===

**Transformation:** All transformations applied simultaneously — identifier renaming (s1) + structural reorganisation (s2) + problem-statement rewrite (s3).

**Resolved instances:** elastic__logstash-16681 (R1,R2,R3,R4,R5), fasterxml__jackson-core-183 (R3), mockito__mockito-3129 (R3,R4,R5)

**Dramatic improvement:** elastic__logstash-16681 (1/5 in s0 → 5/5 in s4 — 100% consistency)

**Instances that dropped from s0 to zero:** elastic__logstash-14970, elastic__logstash-14981 (renaming kills them, same mechanism as s1), google__gson-1093, fasterxml__jackson-databind-1923

---

### elastic__logstash-16681

**[run-1]** _(42 steps, exit_status: submitted via exit_cost)_
1. The agent's first search is `search_dir "PipelineEventBusV2" .` — a renamed class name from the combined transformation. This returns no results (actual class is `PipelineBusV2`). The follow-up `find . -name "PipelineEventBusV2.java"` also fails.
2. **Critical pivot:** Instead of spiralling in failed class-name searches, the agent switches to method-based searches: `search_dir "unregisterSender" logstash-core` and `search_dir "notifyAll" logstash-core/src/main/java/org/logstash/plugins/pipeline`. These are semantic searches for the specific operations described in the deadlock (unregistering while listeners are active, using notify/wait synchronization). Both succeed and directly point to `PipelineBusV2.java`.
3. This method-based fallback strategy produces **9 edits** — vs s0's 2 and s2's 3. The agent makes a much more thorough fix, addressing multiple synchronization paths rather than just the most obvious one. This thoroughness explains the 5/5 consistency: the more comprehensive fix is robust to the different test-execution orderings across 5 independent runs.
4. 2 test runs confirm the fix works. Despite exit_cost, the submitted patches are correct in all 5 runs.
5. The combined transformation has a paradoxical beneficial effect: the renaming forces the agent to give up on class-name search and fall back to semantic/method search, which finds the real bug more reliably. The structural changes further force re-reading of the synchronization code fresh, preventing pattern-match shortcuts. The result is the most consistent and most thorough fix across all strategies for this instance.

**[run-2]** _(47 steps, exit_status: submitted via exit_cost)_
1. Six searches: initial class-name failures (`"class PipelineEventBusV2"`, `"PipelineEventBusV2"`), then breadth-first fallbacks: `search_dir "pipelinebus"` (lowercase, no class or "V2" suffix), `search_dir "PipelineBusV2" logstash-core/src test qa spec .` (multi-directory combined search), `search_dir "PipelineBusV2"` (global), and finally `find_file "PipelineBusV2Test.java"` (targeting the test class by filename).
2. The cascade from renamed class → generic name → multi-directory search → test class lookup shows the agent systematically broadening its search scope after each failure — a robust fallback strategy that R1 also executes (via method search), but R2 reaches success via the test-class filename instead.
3. Only 3 edits and 0 test runs. The agent finds the implementation via the test class name, makes minimal synchronization edits, and submits at cost limit.
4. The fix is correct despite 0 tests: the rewritten problem statement (part of s4) provides enough implementation context that the agent can reason about the deadlock fix statically. Matches R1's 0-test-yet-correct pattern.

**[run-3]** _(43 steps, exit_status: submitted via exit_cost)_
1. Four searches: `find_file "PipelineEventBusV2.java"` → `search_dir "PipelineEventBusV2"` → `find . -iname "*pipeline*bus*" -o -iname "*eventbus*"` (wildcard, case-insensitive) → `search_dir "registerSender("`. The wildcard find is the bridge: it returns `PipelineBusV2.java` without knowing the exact renamed class name. The final `registerSender(` search is method-level.
2. 2 edits and 2 test runs: `./gradlew :logstash-core:test --tests org.logstash.plugins.pipeline.PipelineBusT*`. The agent validates both before and after the fix with actual test execution — one of only two runs (R3, alongside potentially R5 in some strategies) that runs tests under s4 for this instance.
3. Fewer edits than R1 (2 vs 9) but tests its fix — a different trade-off than R1's comprehensive-edit-no-test approach. R3's 2 edits target the most critical synchronization path.
4. The wildcard find `*pipeline*bus*` is the most reliable of the fallback strategies seen across all runs: it doesn't depend on knowing the suffix "V2" or the prefix "Event", just that "pipeline" and "bus" are part of the filename. This pattern succeeds in all runs where it's used.

**[run-4]** _(44 steps, exit_status: submitted via exit_cost)_
1. Six searches with a unique addition: `search_dir "findDeadlockedThreads" logstash-core/src/test/java`. This searches for a JVM thread deadlock detection method in the test code — the agent is looking for an existing test that detects deadlocks in the pipeline bus. This test-code search is unique to R4 across all strategies.
2. Also opens the `PipelineBus.java` interface (via `search_dir "interface PipelineBus"`). R4 is one of only two runs (along with s1 R1) that explicitly reads the interface definition before implementing the fix.
3. 3 edits and 1 test run. The `findDeadlockedThreads` search indicates the agent found a test utility that checks for JVM-level deadlocks — a sophisticated validation approach. The 1 test run uses this utility.
4. The interface + deadlock-detection strategy is the most architecturally sophisticated approach across all 100 agent runs for this instance. Despite the sophistication, only 3 edits — the agent is precise once it understands the synchronization contract from the interface.

**[run-5]** _(45 steps, exit_status: submitted via exit_cost)_
1. Eight searches — the most of any s4 run for this instance. Includes `find . -type f | grep -E 'Pipeline.*(Bus|Event).*\.java$'` (regex-filtered find for all pipeline bus files), `search_dir "class AddressState"`, `search_dir "unregisterSender("` (twice — with different scopes), `find . -type f | grep 'PipelineBusV2Test\.java$'`, and `search_dir "class ReceiveResponse"`.
2. The `ReceiveResponse` class search is unique across all 100 runs: it's an internal type used in the pipeline bus protocol. The agent is tracing the full send/receive protocol to understand all the locking points involved in the deadlock.
3. 2 edits and 0 test runs. Despite the most searches of any s4 run for this instance, the fix is minimal — the comprehensive protocol understanding leads to a surgical 2-edit fix targeting the exact lock acquisition order.
4. R5 exemplifies a "thorough research, minimal implementation" pattern: maximum search investment produces minimal targeted edits. The fix is correct (all 5 runs resolve), confirming that deep protocol research is a viable alternative to the broad-fix approach used in R1 (9 edits).

---

### fasterxml__jackson-core-183

**[run-3]** _(48 steps, exit_status: submitted — FEWER steps than s0's 56, 14% more efficient)_
1. **File renamed:** In s4, `TextBuffer.java` becomes `SegmentedTextBuffer.java`. The agent's first search `find_file "SegmentedTextBuffer.java" src` immediately succeeds — the more specific name is easier to target than the generic `TextBuffer`.
2. The rename is semantically meaningful: `SegmentedTextBuffer` explicitly encodes the implementation's segmented-array design. The agent's subsequent exploration of `ParserBase.java` (which uses `SegmentedTextBuffer`) is more targeted because the class name signals its role.
3. 10 edits and 3 test runs. The fix to `getTextBuffer()` is similar to s0 but the agent executes it more efficiently (48 vs 56 steps). The clearer name reduces the "what does this class do?" exploration overhead.
4. This is a case where the rename transformation actually helps rather than hinders: the new name is unambiguous and more descriptive, making the agent's search and navigation more direct.

---

### mockito__mockito-3129

**[run-3]** _(66 steps, exit_status: submitted via exit_cost)_
1. **All names changed:** `MockUtil` → `MockUtilities`, `MockitoPlugins` interface → `MockitoPluginRegistry`, `DefaultMockitoPlugins` → `DefaultMockitoPluginRegistry`. The naming now follows the Registry pattern precisely, making the interface/implementation relationship explicit.
2. The agent searches for `"class MockitoPluginRegistry|interface MockitoPluginRegistry"` in one query — demonstrating it has correctly inferred the new naming convention from the problem statement and can search for both forms simultaneously.
3. 8 searches explore `"getMockMaker"`, `"MockitoPluginRegistry"`, `"getInlineMockMaker"`, and the test file `"MockitoPluginsTest|framework().getPlugins()"`. The method-name searches (`getMockMaker`, `getInlineMockMaker`) are preserved across transformations and serve as stable anchors.
4. 10 edits, 0 test runs. Like s3's mockito trajectory, the agent reasons about correctness statically without test execution. The Registry naming pattern (both interface `MockitoPluginRegistry` and implementation `DefaultMockitoPluginRegistry`) makes the structural relationship unambiguous and reduces cyclic editing.
5. Solved in R3, R4, R5 (3/5). Not as consistent as s1 or s3 (both 4/5), possibly because the combination of renaming + structural moves requires more steps to orient, leaving less budget for iteration.

**[run-4]** _(80 steps, exit_status: submitted via exit_cost)_
1. Eight searches: `search_dir "getMockMaker" src subprojects`, `search_dir "getMockMaker"`, `search_dir "getInlineMockMaker"`, `search_dir "implements MockitoPluginRegistry"` (the renamed interface from s4), `search_dir "getInlineMockMaker" src/test`, `search_dir "getMockMaker()" src/main/java`, `search_dir "getPlugins()" src/main/java src/test/java`, `search_dir "getPlugins()"`. The repeated searches with narrowing scope again show systematic fallback.
2. Only 1 edit — the lowest edit count of any resolved mockito trajectory across all strategies. Despite 80 steps and 8 searches, the agent reaches a 1-edit fix and submits at cost. The combined renaming (interface now called `MockitoPluginRegistry`) creates enough orientation overhead that the agent spends most of its budget searching rather than editing.
3. 0 test runs. The single edit is to the correct location (wiring `getMockMaker()` through `MockitoPluginRegistry`). The rewritten problem statement provides enough confidence to submit without test validation.
4. R4 is a budget-exhaustion case: the combination of renaming (new interface name `MockitoPluginRegistry`) and structural moves causes the agent to search 8 times before making its 1 decisive edit. The fix is correct but arrived at with extreme inefficiency — 79 steps of searching before 1 step of fixing.

**[run-5]** _(54 steps, exit_status: submitted)_
1. Seven searches: `search_dir "getInlineMockMaker" src subprojects`, `search_dir "getInlineMockMaker"`, `search_dir "getMockMaker"`, `search_dir "implements MockitoPluginRegistry" src/main/java`, `search_dir "getInlineMockMaker()" src/test`, `search_dir "class Plugins" src/main/java`, `search_dir "implements MockitoPluginRegistry" src`. The `class Plugins` search is unique: the agent is looking for a utility class named `Plugins` (possibly how `DefaultMockitoPlugins` was renamed in s4's combined transformation).
2. 13 edits and 3 test runs — the highest edit count of the resolved s4 mockito runs. The `class Plugins` search finds the renamed utility class, allowing the agent to trace the full plugin resolution chain. This thorough understanding enables comprehensive edits.
3. The 3 test runs (`./gradlew test --tests org.mockitousage.plugins.MockitoPluginsTest`, then `:test` prefix variants) validate at different granularities. The agent confirms the fix at project level and then at task level.
4. R5 is a clean submission (not exit_cost) in 54 steps — more efficient than R3's 66 or R4's 80. The R5 seed produces a trajectory that discovers the right classes earlier (via `class Plugins` search) and then iterates confidently through 13 targeted edits with test validation.

---

## Cross-Cutting Observations

**1. Class-name anchoring is the primary failure mode under s1/s4:**
Instances that rely on a single class as their entry point (DLQ writer for 14970/14981, JsonWriter for gson-1093, TextBuffer for jackson-core-183) fail completely under renaming when the agent cannot correctly infer the new name from the problem statement. The failure is catastrophic — 4–6 consecutive zero-result searches strand the agent before it can pivot.

**2. Method-name searches are more robust than class-name searches:**
For elastic__logstash-16681 in s4, the switch from class search to method search (`unregisterSender`, `notifyAll`) produces a better fix than the class search used in s0. Instances where agents use method-level searches tend to be more resilient to renaming transformations.

**3. Structural transformation is largely transparent for single-class fixes:**
The DLQ writer instances (14970, 14981) are solved at the same or higher rate under s2 as under s0 because the fix is entirely within one method of one class. Method sorting doesn't change the class name, package, or method signature — the only disruption is line number shifting, which the agent handles by re-reading rather than hard-coding locations.

**4. Problem-statement rewrites have instance-specific effects:**
For mockito-3129, s3 nearly quadruples the success rate (1/5 → 4/5). For gson-1093, it preserves performance (2/5 → 2/5). For elastic__logstash-16579, it unlocks a previously impossible instance. There is no universal direction — the effect depends on whether the original problem statement was the limiting factor.

**5. The combined s4 transformation creates a novel and more reliable search strategy for elastic__logstash-16681:**
The rename breaks the agent's first-choice search strategy, forcing a fallback to semantic method searches. This fallback turns out to be better than the original strategy, producing 9 edits vs s0's 2 and 100% consistency vs s0's 20%. This is the clearest example in the dataset of a metamorphic transformation accidentally improving agent behavior by disrupting an overfit shortcut.

**6. mockito__mockito-3129 is the inverse of the DLQ pattern:**
In s0, the agent cycles through edits in 4 of 5 runs and produces a working fix only once. Under all other strategies, the pass rate improves (4/5 in s1, 2/5 in s2, 4/5 in s3, 3/5 in s4). This pattern is consistent with the agent having a memorized-but-imprecise solution for the original Mockito codebase that it applies incorrectly most of the time. Transformations that change the class names disrupt this shortcut and force genuine step-by-step problem-solving, which is more reliable.
