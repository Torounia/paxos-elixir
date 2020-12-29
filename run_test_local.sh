killall -9 beam.smp 2>/dev/null
/bin/rm -f *.beam
elixir --sname coord test_script_local.exs

$SHELL