#:os.cmd('/bin/rm -f *.beam')

# Replace with your own implementation source files
IEx.Helpers.c("beb.ex", ".")
IEx.Helpers.c("paxos.ex", ".")
# ##########

IEx.Helpers.c("test_harness.ex", ".")
IEx.Helpers.c("paxos_test.ex", ".")
IEx.Helpers.c("uuid.ex", ".")

# Replace the following with the short host name of your machine (case sensitive!)
host = "cim-ts-node-02"
# ###########

get_node = fn -> String.to_atom(UUID.uuid1() <> "@" <> host) end

# Use get_dist_config.(n) to generate a multi-node configuration
# consisting of n processes, each one on a different node
get_dist_config = fn n ->
  for i <- 1..n,
      into: %{},
      do: {String.to_atom("p" <> to_string(i)), {get_node.(), {:val, Enum.random(201..210)}}}
end

# Use get_local_config.(n) to generate a single-node configuration
# consisting of n processes, all running on the same node
get_local_config = fn n ->
  for i <- 1..n,
      into: %{},
      do: {String.to_atom("p" <> to_string(i)), {:local, {:val, Enum.random(201..210)}}}
end

test_suite = [
  #   test case, configuration, number of times to run the case, description
  # {&PaxosTest.run_simple/3, get_local_config.(3), 1, "No failures, no concurrent ballots"},
  # {&PaxosTest.run_simple_2/3, get_dist_config.(5), 1, "No failures, 2 concurrent ballots"},
  {&PaxosTest.run_simple_many/3, get_dist_config.(5), 1, "No failures, many concurrent ballots"},
  # {&PaxosTest.run_non_leader_crash/3, get_dist_config.(3), 1,
  #  "One non-leader crashes, no concurrent ballots"},
  # {&PaxosTest.run_minority_non_leader_crash/3, get_dist_config.(7), 1,
  #  "Minority non-leader crashes, no concurrent ballots"},
  # {&PaxosTest.run_leader_crash_simple/3, get_dist_config.(7), 1,
  #  "Leader crashes, no concurrent ballots"},
  # {&PaxosTest.run_leader_crash_simple_2/3, get_dist_config.(7), 1,
  #  "Leader and some non-leaders crash, no concurrent ballots"},
  # {&PaxosTest.run_leader_crash_complex/3, get_dist_config.(11), 1,
  #  "Cascading failures of leaders and non-leaders"},
  # {&PaxosTest.run_leader_crash_complex_2/3, get_dist_config.(11), 1,
  #  "Cascading failures of leaders and non-leaders, random delays"}
]

Node.stop()
Node.start(get_node.(), :shortnames)

Enum.reduce(test_suite, length(test_suite), fn {func, config, n, doc}, acc ->
  IO.puts(:stderr, "============")
  IO.puts(:stderr, "#{inspect(doc)}, #{inspect(n)} time#{if n > 1, do: "s", else: ""}")
  IO.puts(:stderr, "============")

  for _ <- 1..n do
    res = TestHarness.test(func, Enum.shuffle(Map.to_list(config)))

    {vl, al, ll} =
      Enum.reduce(res, {[], [], []}, fn {_, _, s, v, a, {:message_queue_len, l}}, {vl, al, ll} ->
        if s != :killed,
          do: {[v | vl], [a | al], [l | ll]},
          else: {vl, al, ll}
      end)

    termination = :none not in vl
    agreement = termination and MapSet.size(MapSet.new(vl)) == 1
    {:val, agreement_val} = if agreement, do: hd(vl), else: {:val, -1}
    # TODO: Is there a validity test where all input values are the same?
    validity = agreement_val in 201..210
    safety = agreement and validity
    too_many_attempts = (get_att = fn a -> 10 - a + 1 end).(Enum.max(al)) > 5
    too_many_messages_left = Enum.max(ll) > 10

    if termination and safety do
      warn = if too_many_attempts, do: [{:too_many_attempts, get_att.(Enum.max(al))}], else: []

      warn =
        if too_many_messages_left,
          do: [{:too_many_messages_left, Enum.max(ll)} | warn],
          else: warn

      IO.puts(:stderr, if(warn == [], do: "PASS", else: "PASS (#{inspect(warn)})"))
      # IO.puts(:stderr, "#{inspect res}")
    else
      IO.puts(:stderr, "FAIL\n\t#{inspect(res)}")
    end
  end

  IO.puts(:stderr, "============#{if acc > 1, do: "\n", else: ""}")
  acc - 1
end)

Node.stop()
System.halt()
