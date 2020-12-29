# Paxos based on Elixir

Paxos distributed consensus algorithm implemented using Elixir Erlnag. Paxos is a family of protocols for solving consensus in a network of unreliable or fallible processors. 

## Description

### Objective of the algorithm:

To maintain the same ordering of commands among multiple replicas so that all the replicas eventually converge to the same value.
Ref: [Paxos Made Simple by Leslie Lamport] (https://lamport.azurewebsites.net/pubs/paxos-simple.pdf)

This distributed consensus algorithm is implemented based on Erlang/ Elixir distributed programming architecture and the easy to use message passing methods comes with Elixir. 

### main files are:

- paxos.ex: main Paxos layer
- beb.ex: best effort broadcast (BEB) layer the Paxos layer is built upon. 
- test_harness.ex: testing framework
- paxos_test.ex: collection of unit tests for the Paxos protocol
- test_script.exs: the test driver script

### Paxos interface:

- start(name, participants, upper): start an instance of a Paxos layer process; returns PID
- propose(pid, value): propose a value via the Paxos  process associated with PID
- start_ballot(pid): ask the Paxos process process associated with PID to start a new ballot as the leader of that ballot

## Usage

```Shell
run_test_local.sh #run this for testing a single node (proccesor to proccesor)

run_test.sh #run this for testing in distibuted model (nodes to nodes)
```




