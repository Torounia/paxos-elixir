## Paxos Consensus Algorithm implemented in Elixir
 

Files:
- paxos.ex: main Paxos layer source
- beb.ex: best effort broadcast (BEB) layer the Paxos layer is built upon. 

- test_harness.ex: testing framework
- paxos_test.ex: collection of unit tests for the Paxos protocol
- test_script_local.exs: the test driver script for the local tests


Paxos interface:
- start(name, participants, upper): start an instance of a Paxos layer process; returns PID
- propose(pid, value): propose a value via the Paxos  process associated with PID
- start_ballot(pid): ask the Paxos process process associated with PID to start a new ballot as the leader of that ballot

- To test run the run_test_local.sh file.
