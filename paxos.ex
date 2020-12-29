defmodule Paxos do
  def start(name, participants, upper) do
    # Initiation of state. State stores the status of each parameter used by the consensus algorithm
    state = %{
      name: name,
      upper: upper,
      participants: participants,
      number_of_particiants: length(participants),
      set_input: nil,
      comms_layer: nil,
      proposer_prepare_request_id: 0,
      phs1_max_ID: 0,
      accepted_val: 0,
      proposal_accepted: False,
      proposal_accepted_ID: 0,
      acceptors_phs1: [],
      acceptors_phs2: []
    }

    # Spawn of the Paxos main instance
    pid = spawn(Paxos, :main, [state])

    # Start the BEB communication layer
    comms_layer = BestEffortBC.start(name, participants, pid)

    # Send the pid of the BEB process to Paxos.main function
    send(pid, {:lower, comms_layer})
    # return the PID to the test framework
    pid
  end

  # Used by the test framework to input a value to the consensus algorithm. It sends a message to Paxos.main of the new value.
  def propose(pid, val) do
    send(pid, {:set_input, val})
  end

  # Used by the test framework to tell a process to start a ballot with the given input value from above
  def start_ballot(pid) do
    # Tell the main function to begin a ballot
    send(pid, {:start_ballot})
  end

  def main(state) do
    state =
      receive do
        # Setting the input to the consencus protocol
        {:set_input, val} ->
          %{state | set_input: val}

        # Setting the Best Effort Broadcast communication layer
        {:lower, lower} ->
          %{state | comms_layer: lower}

        # Proposer role, start ballot as instructed by the test framework
        {:start_ballot} ->
          # IO.inspect("I am #{state.name} and I am startng a ballot")
          proposer_phs1(state)

        # Proposal role, receive a promise from the acceptors (without a previous accepter proposal)
        {:promise, name, proposed_id} ->
          # IO.inspect("I am #{state.name} as proposer and I received a promide from #{name} for ballot ID #{proposed_id}")
          proposer_phs2(state, name, proposed_id)

        # Proposal role, receive a promise from the acceptors (with a previous accepter proposal)
        {:promise, name, proposed_id, last_accepted_max_iD, acceptor_accepted_val} ->
          # IO.inspect("I am #{state.name} as proposer and I received a promide from #{name} for ballot ID #{proposed_id} but there is previous accepted value: #{inspect(acceptor_accepted_val)}")
          proposer_phs2(state, name, proposed_id, last_accepted_max_iD, acceptor_accepted_val)

        # Proposal role, receive acceptance message from the acceptors
        {:accepted, name, accepted_ID, value} ->
          # IO.inspect("I am #{state.name} as proposer and I received an accept from #{name} for ballot ID #{accepted_ID}")
          proposer_last(state, name, accepted_ID, value)

        # Proposal role, propose failed, increase ID and try again
        {:try_again, _from, _previous_max_ballot} ->
          state

        # # IO.inspect("I am #{state.name} as proposer and I received a try again from #{from} with previous max ballot #{previous_max_ballot}")
        # proposer_phs1(state, True, previous_max_ballot)

        # Broadcast messages received
        {:output, :bc_receive, _origin, msg} ->
          case msg do
            # phase 1 proposer sends prepare request
            {:prepere_request, proposer, prepare_id} ->
              acceptor_phs1(state, proposer, prepare_id)

            # phase 2 proposer sends propose request
            {:propose, proposer, propose_id, value} ->
              acceptor_phs2(state, proposer, propose_id, value)

            # Accepted message by the acceptors to the learners. When accepted message received, update the learnerd parameters
            {:accepted, accepted_id, accepted_val} ->
              state = %{state | proposal_accepted: True}
              state = %{state | accepted_val: accepted_val}
              state = %{state | proposal_accepted_ID: accepted_id}
              # give some time to the proposer to communicate consensus to the test framework
              :timer.sleep(200)
              # stop the broadcast layer
              BestEffortBC.stop(state.comms_layer, self())
              # As acceptor and learner inform the test framework that consensus is reached.
              send(state.upper, {:decide, accepted_val})
              state
          end
      end

    main(state)
  end

  # Proposer Phase 1
  def proposer_phs1(state, prepare_failed \\ False, previous_max_ballot \\ 0) do
    # If this is the first time proposing a value, create a unique ID bound to the proccess number
    if prepare_failed == False do
      n = String.to_integer(String.slice(Atom.to_string(state.name), 1, 1)) + 5
      # IO.puts("#{state.name} first time ballot #{n}")
      BestEffortBC.bc_send(state.comms_layer, {:prepere_request, self(), n})
      state = %{state | proposer_prepare_request_id: n}
      main(state)
    else
      # otherwise if trying again, increment the old ID by 5, broadcast the request and update the state parameter
      # IO.puts(
      #     "#{state.name}proposer request id #{state.proposer_prepare_request_id} previous max #{
      #       previous_max_ballot
      #     }"
      #   )
      if state.proposer_prepare_request_id <= previous_max_ballot do
        # IO.puts(
        #   "#{state.name}proposer request id #{state.proposer_prepare_request_id} previous max #{
        #     previous_max_ballot
        #   }"
        # )
        state = %{state | proposer_prepare_request_id: previous_max_ballot + 5}
        proposer_phs1(state, prepare_failed, previous_max_ballot)
      end

      # IO.puts("#{state.name}Increment #{n}")
      BestEffortBC.bc_send(
        state.comms_layer,
        {:prepere_request, self(), state.proposer_prepare_request_id}
      )

      main(state)
    end

    main(state)
  end

  # Acceptor Phase 1
  def acceptor_phs1(state, proposer, prepare_id) do
    # if the prepare ID is smaller that previous IDs then send try again message
    # IO.inspect("I am #{state.name} as acceptor on phase 1 and #{inspect(proposer)} promosed ID: #{prepare_id}")
    if prepare_id <= state.phs1_max_ID do
      # IO.inspect("I am #{state.name} as acceptor on phase 1 and #{inspect(proposer)} promosed ID: #{prepare_id} but try again, max ID is #{state.phs1_max_ID}")
      send(proposer, {:try_again, state.name, state.phs1_max_ID})
    else
      # else save the propsed ID as the biggest received so far
      # IO.inspect("I am #{state.name} as acceptor on phase 1 and #{inspect(proposer)} promosed ID: #{prepare_id}, ID is bigger than #{state.phs1_max_ID}")
      state = %{state | phs1_max_ID: prepare_id}
      # check if the there are previous accepted proposals and if so send to the
      # proposer the prepare ID, the previously accepted ID and the previously accepted value
      if state.proposal_accepted == True do
        # IO.inspect("I am #{state.name} as acceptor on phase 1 and #{inspect(proposer)} promosed ID: #{prepare_id}, ID is bigger than #{state.phs1_max_ID} but I have accepter alread under ballot #{state.proposal_accepted_ID}")
        send(
          proposer,
          {:promise, state.name, prepare_id, state.proposal_accepted_ID, state.accepted_val}
        )
      end

      # else send to the proposer a promise message with the acceptor name and the prepare ID
      send(proposer, {:promise, state.name, prepare_id})
      main(state)
    end

    main(state)
  end

  # Proposer phase 2. The proposer is checking if there is majority from phase 1 and procceds to phase 2
  def proposer_phs2(
        state,
        name,
        proposed_id,
        _last_accepted_max_iD \\ 0,
        acceptor_accepted_val \\ nil
      ) do
    # check if the acceptor is not already in the list of the acceptors for phase 1 and adds it to the list
    # IO.inspect("I am #{state.name} as proposer on phase 2 with proposed ID #{proposed_id}")
    if name not in state.acceptors_phs1 do
      state = %{state | acceptors_phs1: [name | state.acceptors_phs1]}
      proposer_phs2(state, name, proposed_id)
    end

    # check for majority
    if length(state.acceptors_phs1) >= round(state.number_of_particiants / 2) do
      # IO.inspect("I am #{state.name} as proposer on phase 2 with proposed ID #{proposed_id} and have a majority")
      # if majority, check if any of the acceptors provided a previously accepter value.
      if acceptor_accepted_val != nil do
        # if yes, provide update the input value to the previously accepted value and
        # IO.inspect("I am #{state.name} as proposer on phase 2 with proposed ID #{proposed_id} and have a majority but there is an accepted value #{inspect(acceptor_accepted_val)}")
        state = %{state | set_input: acceptor_accepted_val}

        # broadcast a propose message with the proposed from phase 1 and the previously accepted value.
        # IO.inspect("I am #{state.name} as proposer on phase 2 with proposed ID #{proposed_id} and have a majority Broadcasting my value: #{inspect(acceptor_accepted_val)}")
        BestEffortBC.bc_send(
          state.comms_layer,
          {:propose, self(), proposed_id, acceptor_accepted_val}
        )
      else
        # else, if no previously accepted values, broadcast a propose with owns input value and proposed ID
        # IO.inspect("I am #{state.name} as proposer on phase 2 with proposed ID #{proposed_id} and have a majority Broadcasting my value: #{acceptor_accepted_val}")
        BestEffortBC.bc_send(state.comms_layer, {:propose, self(), proposed_id, state.set_input})
      end

      main(state)
    end

    main(state)
  end

  # The acceptor for phase 2 will check to see if the received ID is the largest it has received so far and if so it will accept the value
  def acceptor_phs2(state, proposer, propose_id, value) do
    # IO.inspect("I am #{state.name} as acceptor on phase 2 and #{inspect(proposer)} promosed ID: #{propose_id} with value #{inspect(value)}")
    # check if the received ID is the largest it has received so far,
    if propose_id >= state.phs1_max_ID do
      # if so, update the state parameters
      state = %{state | proposal_accepted: True}
      state = %{state | proposal_accepted_ID: propose_id}
      state = %{state | accepted_val: value}
      # communicate acceptance to the proposer
      # IO.inspect("I am #{state.name} as acceptor on phase 2 and #{inspect(proposer)} promosed ID: #{propose_id} with value #{inspect(value)}, the proposed ID #{propose_id} is the biggest I have seen and I send Accept")
      send(proposer, {:accepted, state.name, propose_id, value})
      # communicate acceptance to the rest of the network or other learners
      BestEffortBC.bc_send(state.comms_layer, {:accepted, propose_id, value})
      main(state)
    else
      # IO.inspect("I am #{state.name} as acceptor on phase 2 and #{inspect(proposer)} with promosed ID: #{propose_id} failed. try again, max ID is #{state.phs1_max_ID}")
      # if the ID received is not the biggest then send to the proposer a try again message to re start the proccess.
      send(proposer, {:try_again, state.name, state.phs1_max_ID})
    end

    main(state)
  end

  # Last, the proposer will check the acceptors of phase 2 and if majority, it will inform the test framework
  def proposer_last(state, name, accepted_ID, value) do
    # IO.inspect("I am #{state.name} as proposer on last phase with proposed ID #{accepted_ID} and #{inspect(value)}")
    if name not in state.acceptors_phs2 do
      state = %{state | acceptors_phs2: [name | state.acceptors_phs2]}
      proposer_last(state, name, accepted_ID, value)
    end

    if length(state.acceptors_phs2) >= round(state.number_of_particiants / 2) do
      # IO.inspect("I am #{state.name} as proposer on last phase with proposed ID #{accepted_ID} and have a majority, sending above")
      send(state.upper, {:decide, value})
      main(state)
    end

    # IO.inspect("I am #{state.name} as proposer on last phase with proposed ID #{accepted_ID} and dont have a majority yet")
    main(state)
  end
end
