#!/usr/bin/env lua
-- Test performance of dynamic phrase cache

package.path = package.path .. ";/Users/mac/Library/Rime/lua/?.lua"

local core = require("xmjd6.dynamic_phrase_core")

-- Create a test file with many entries
local function create_test_file(path, count)
    local f = io.open(path, "w")
    f:write("# Test file with " .. count .. " entries\n")
    for i = 1, count do
        local text = "测试词" .. i
        local code = "test" .. i
        f:write(text .. "\t" .. code .. "\n")
    end
    -- Add some with same prefixes
    for i = 1, 50 do
        f:write("前缀词" .. i .. "\tqz" .. string.format("%02d", i) .. "\n")
    end
    f:close()
end

local function measure_time(func, name)
    local start = os.clock()
    func()
    local elapsed = os.clock() - start
    print(string.format("%s: %.6f seconds", name, elapsed))
    return elapsed
end

local function test_lookup_performance(path, iterations)
    print("\n=== Testing lookup performance ===")
    print("Iterations: " .. iterations)

    -- First call (cold cache)
    measure_time(function()
        core.lookup("test500", path)
    end, "First lookup (cold cache)")

    -- Subsequent calls (warm cache)
    local time = measure_time(function()
        for i = 1, iterations do
            core.lookup("test" .. (i % 1000), path)
        end
    end, iterations .. " cached lookups")

    print(string.format("Average per lookup: %.6f seconds", time / iterations))
end

local function test_prefix_performance(path, iterations)
    print("\n=== Testing prefix lookup performance ===")
    print("Iterations: " .. iterations)

    -- First call (cold cache)
    measure_time(function()
        core.lookup_prefix("qz", path)
    end, "First prefix lookup (cold cache)")

    -- Subsequent calls (warm cache)
    local time = measure_time(function()
        for i = 1, iterations do
            core.lookup_prefix("qz", path)
        end
    end, iterations .. " cached prefix lookups")

    print(string.format("Average per lookup: %.6f seconds", time / iterations))
end

local function test_cache_invalidation(path)
    print("\n=== Testing cache invalidation ===")

    -- Load into cache
    core.lookup("test1", path)
    print("Cache loaded")

    -- Add a new entry
    measure_time(function()
        core.add_phrase("新词", "xc", path)
    end, "Add phrase (triggers cache clear)")

    -- Next lookup should rebuild cache
    measure_time(function()
        local results = core.lookup("xc", path)
        assert(#results == 1, "New phrase not found!")
        assert(results[1].text == "新词", "Wrong text!")
    end, "Lookup after add (cache rebuild)")

    print("✓ Cache invalidation works correctly")
end

local function run_tests()
    local test_path = "/tmp/dynamic_phrase_test.txt"
    local entry_count = 1000

    print("Creating test file with " .. entry_count .. " entries...")
    create_test_file(test_path, entry_count)

    -- Clear any existing cache
    core.clear_cache()

    test_lookup_performance(test_path, 1000)
    test_prefix_performance(test_path, 1000)
    test_cache_invalidation(test_path)

    -- Cleanup
    os.remove(test_path)

    print("\n✓ All tests passed!")
    print("\n=== Performance Summary ===")
    print("With cache: O(1) lookup via hash table")
    print("Without cache: O(n) lookup via linear scan")
    print("Expected speedup: ~100-1000x for large dictionaries")
end

-- Run tests
local ok, err = pcall(run_tests)
if not ok then
    print("Error: " .. tostring(err))
    os.exit(1)
end
