killall -9 beam.smp 2>/dev/null
/bin/rm -f *.beam
iex --sname alice --erl -noshell test_script.exs 2>1 >/dev/null &
iex --sname bob --erl -noshell test_script.exs 2>1 >/dev/null &
iex --sname charlie --erl -noshell test_script.exs 2>1 >/dev/null &
iex --sname darren --erl -noshell test_script.exs 2>1 >/dev/null &
iex --sname elias --erl -noshell test_script.exs 2>1 >/dev/null &
iex --sname coord test_script.exs