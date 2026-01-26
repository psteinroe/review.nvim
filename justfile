_default:
    just --list -u

# Run all tests
test:
    nvim --headless -u tests/init.lua -c "lua MiniTest.run()"

# Run unit tests only
test-unit:
    nvim --headless -u tests/init.lua -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.glob('tests/unit/*.lua', true, true) end } })"

# Run integration tests only
test-integration:
    nvim --headless -u tests/init.lua -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.glob('tests/integration/*.lua', true, true) end } })"

# Lint with luacheck
lint:
    luacheck lua/ tests/ --no-unused-args --no-max-line-length

# Format with stylua
format:
    stylua lua/ tests/

# Check formatting
format-check:
    stylua --check lua/ tests/

# Human-in-the-loop Ralph: run once, watch, then run again
ralph-once:
    claude --dangerously-skip-permissions "@PLAN.md @progress.txt \
    1. Read the PLAN.md and progress.txt file. \
    2. Find the next incomplete task from the Implementation Order and implement it. \
    3. Run tests if they exist (just test). \
    4. Commit your changes with a descriptive message. \
    5. Update progress.txt with what you did in the session format. \
    ONLY DO ONE TASK AT A TIME. \
    Focus on quality over speed."

# AFK Ralph: run multiple iterations autonomously
ralph-loop iterations="50":
    #!/usr/bin/env bash
    set -e
    for ((i=1; i<={{iterations}}; i++)); do
        echo "=== Ralph iteration $i/{{iterations}} ==="
        result=$(claude --dangerously-skip-permissions -p "@PLAN.md @progress.txt \
        1. Read the PLAN.md and progress.txt file. \
        2. Find the next incomplete task from the Implementation Order and implement it. \
        3. Run tests if they exist. \
        4. Commit your changes with a descriptive message. \
        5. Update progress.txt with what you did. \
        ONLY DO ONE TASK AT A TIME. \
        If all tasks in the Implementation Order are complete, output <promise>COMPLETE</promise>.")

        echo "$result"

        if [[ "$result" == *"<promise>COMPLETE</promise>"* ]]; then
            echo "=== PLAN.md complete after $i iterations ==="
            exit 0
        fi
    done
    echo "=== Completed {{iterations}} iterations ==="

# Show current progress
progress:
    @cat progress.txt

# Show implementation order from PLAN.md
plan:
    @grep -A 50 "## Implementation Order" PLAN.md | head -60
