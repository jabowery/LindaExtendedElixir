defmodule Linda do
  @moduledoc """
  An implementation of the extended Linda coordination language.

  The tuple space is a multiset of tuples. Tuples are represented as Elixir
  tuples. A tuple pattern may include the wildcard `"*"` (or the atom `:_`)
  to match any value.

  ## Basic Operations

    * `output(tuple)` – Adds a tuple to the space.
    * `input(pattern)` – Removes a tuple matching the given pattern (blocking until available).
    * `read(pattern)` – Reads (without removing) a tuple matching the given pattern (blocking until available).

  ## Collective Operations

    * Blocking:
      - `coll_input(templates, condition)` – Blocks until the condition is met and then
        removes one matching tuple per template.
      - `coll_read(templates, condition)` – Blocks until the condition is met and then
        returns one matching tuple per template.
      - `coll_await(templates, condition)` – Blocks until an absence condition is met.
    * Non–blocking variants:
      - `coll_inputp(templates, condition)`
      - `coll_readp(templates, condition)`
      - `coll_awaitp(templates, condition)`

  ## Conditions

  The following conditions are available (passed as atoms):

      - `:ALL_PRESENT`    – every template must match at least one tuple.
      - `:NOT_ALL_PRESENT`– at least one template is not matched.
      - `:ALL_ABSENT`     – no template is matched.
      - `:NOT_ALL_ABSENT` – at least one template is matched.

  ## Examples

  In each example we start the server and later stop it. (In real usage you would
  start the server only once.)

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.output({"foo", 42})
      :ok
      iex> Linda.read({"foo", 42})
      {"foo", 42}
      iex> GenServer.stop(Linda)
      :ok

  Example of a blocking collective removal (barrier synchronization):

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.output({"done", 1})
      :ok
      iex> Linda.output({"done", 2})
      :ok
      iex> Linda.coll_input([{"done", 1}, {"done", 2}], :ALL_PRESENT)
      [{"done", 1}, {"done", 2}]
      iex> GenServer.stop(Linda)
      :ok

  Example of a blocking collective read with a wildcard (resource pool):

      iex> {:ok, _} = Linda.start_link()
      iex> spawn(fn ->
      ...>   :timer.sleep(100)
      ...>   Linda.output({"resource", "free", 123})
      ...> end)
      iex> Linda.coll_read([{"resource", "free", "*"}], :NOT_ALL_ABSENT)
      [{"resource", "free", 123}]
      iex> GenServer.stop(Linda)
      :ok

  Example of non-blocking collective operations:

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.coll_inputp([{"bar", 99}], :ALL_PRESENT)
      false
      iex> Linda.output({"bar", 99})
      :ok
      iex> Linda.coll_inputp([{"bar", 99}], :ALL_PRESENT)
      {true, [{"bar", 99}]}
      iex> GenServer.stop(Linda)
      :ok

  """

  use GenServer

  ## Public API

  @doc """
  Starts the Linda tuple–space server.

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> GenServer.stop(Linda)
      :ok
  """
  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      %{tuples: [], pending: [], next_op_id: 1},
      Keyword.merge(opts, name: __MODULE__)
    )
  end

  @doc """
  Adds a tuple to the space.

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.output({"example", 1})
      :ok
      iex> GenServer.stop(Linda)
      :ok
  """
  def output(tuple) do
    GenServer.cast(__MODULE__, {:out, tuple})
  end

  @doc """
  Removes a tuple matching the given pattern (blocking until available).

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.output({"item", 10})
      :ok
      iex> Linda.input({"item", 10})
      {"item", 10}
      iex> GenServer.stop(Linda)
      :ok
  """
  def input(pattern) do
    GenServer.call(__MODULE__, {:input, pattern}, :infinity)
  end

  @doc """
  Reads (without removing) a tuple matching the given pattern (blocking until available).

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.output({"read_me", "yes"})
      :ok
      iex> Linda.read({"read_me", "yes"})
      {"read_me", "yes"}
      iex> GenServer.stop(Linda)
      :ok
  """
  def read(pattern) do
    GenServer.call(__MODULE__, {:read, pattern}, :infinity)
  end

  @doc """
  Collective removal. Blocks until the condition is met.

  When used with a presence condition (e.g. `:ALL_PRESENT` or `:NOT_ALL_ABSENT`)
  one matching tuple is removed for each template in `templates`.

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.output({"done", 1})
      :ok
      iex> Linda.output({"done", 2})
      :ok
      iex> Linda.coll_input([{"done", 1}, {"done", 2}], :ALL_PRESENT)
      [{"done", 1}, {"done", 2}]
      iex> GenServer.stop(Linda)
      :ok
  """
  def coll_input(templates, condition) do
    GenServer.call(__MODULE__, {:coll_input, templates, condition}, :infinity)
  end

  @doc """
  Collective read. Blocks until the condition is met.

  Returns a list of tuples (one per template) that match.

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.output({"status", "ok"})
      :ok
      iex> Linda.coll_read([{"status", "ok"}], :ALL_PRESENT)
      [{"status", "ok"}]
      iex> GenServer.stop(Linda)
      :ok
  """
  def coll_read(templates, condition) do
    GenServer.call(__MODULE__, {:coll_rd, templates, condition}, :infinity)
  end

  @doc """
  Collective await. Blocks until an absence condition is met.

  Returns `true`.

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> # Initially there is no tuple {"empty", "slot"}
      iex> Linda.coll_await([{"empty", "slot"}], :ALL_ABSENT)
      true
      iex> GenServer.stop(Linda)
      :ok
  """
  def coll_await(templates, condition) do
    GenServer.call(__MODULE__, {:coll_await, templates, condition}, :infinity)
  end

  @doc """
  Non-blocking variant of coll_in. Returns `{true, result}` if the condition is met,
  or `false` otherwise.

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.coll_inputp([{"nb", 1}], :ALL_PRESENT)
      false
      iex> Linda.output({"nb", 1})
      :ok
      iex> Linda.coll_inputp([{"nb", 1}], :ALL_PRESENT)
      {true, [{"nb", 1}]}
      iex> GenServer.stop(Linda)
      :ok
  """
  def coll_inputp(templates, condition) do
    GenServer.call(__MODULE__, {:coll_inputp, templates, condition})
  end

  @doc """
  Non-blocking variant of coll_rd. Returns `{true, result}` if the condition is met,
  or `false` otherwise.

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.coll_readp([{"nb_read", 2}], :ALL_PRESENT)
      false
      iex> Linda.output({"nb_read", 2})
      :ok
      iex> Linda.coll_readp([{"nb_read", 2}], :ALL_PRESENT)
      {true, [{"nb_read", 2}]}
      iex> GenServer.stop(Linda)
      :ok
  """
  def coll_readp(templates, condition) do
    GenServer.call(__MODULE__, {:coll_rdp, templates, condition})
  end

  @doc """
  Non-blocking variant of coll_await. Returns `true` if the condition is met,
  or `false` otherwise.

  ## Examples

      iex> {:ok, _} = Linda.start_link()
      iex> Linda.coll_awaitp([{"await", "test"}], :ALL_ABSENT)
      true
      iex> GenServer.stop(Linda)
      :ok
  """
  def coll_awaitp(templates, condition) do
    GenServer.call(__MODULE__, {:coll_awaitp, templates, condition})
  end

  ## GenServer callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  # -- Blocking collective operations --

  @impl true
  def handle_call({:coll_input, templates, condition}, from, state) do
    if condition_met?(state.tuples, templates, condition) do
      {result, new_tuples} = perform_op(:coll_input, templates, state.tuples)
      {:reply, result, %{state | tuples: new_tuples}}
    else
      op = %{
        id: state.next_op_id,
        type: :coll_input,
        condition: condition,
        templates: templates,
        from: from,
        nonblocking: false
      }

      new_state = %{state | next_op_id: state.next_op_id + 1, pending: state.pending ++ [op]}
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call({:coll_rd, templates, condition}, from, state) do
    if condition_met?(state.tuples, templates, condition) do
      {result, _} = perform_op(:coll_rd, templates, state.tuples)
      {:reply, result, state}
    else
      op = %{
        id: state.next_op_id,
        type: :coll_rd,
        condition: condition,
        templates: templates,
        from: from,
        nonblocking: false
      }

      new_state = %{state | next_op_id: state.next_op_id + 1, pending: state.pending ++ [op]}
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call({:coll_await, templates, condition}, from, state) do
    if condition_met?(state.tuples, templates, condition) do
      {:reply, true, state}
    else
      op = %{
        id: state.next_op_id,
        type: :coll_await,
        condition: condition,
        templates: templates,
        from: from,
        nonblocking: false
      }

      new_state = %{state | next_op_id: state.next_op_id + 1, pending: state.pending ++ [op]}
      {:noreply, new_state}
    end
  end

  # -- Non-blocking collective operations --

  @impl true
  def handle_call({:coll_inputp, templates, condition}, _from, state) do
    if condition_met?(state.tuples, templates, condition) do
      {result, new_tuples} = perform_op(:coll_input, templates, state.tuples)
      {:reply, {true, result}, %{state | tuples: new_tuples}}
    else
      {:reply, false, state}
    end
  end

  @impl true
  def handle_call({:coll_rdp, templates, condition}, _from, state) do
    if condition_met?(state.tuples, templates, condition) do
      {result, _} = perform_op(:coll_rd, templates, state.tuples)
      {:reply, {true, result}, state}
    else
      {:reply, false, state}
    end
  end

  @impl true
  def handle_call({:coll_awaitp, templates, condition}, _from, state) do
    if condition_met?(state.tuples, templates, condition) do
      {:reply, true, state}
    else
      {:reply, false, state}
    end
  end

  # -- Non-collective (single tuple) operations --

  @impl true
  def handle_call({:input, pattern}, from, state) do
    if exists_match?(state.tuples, pattern) do
      {result, new_tuples} = perform_op(:coll_input, [pattern], state.tuples)
      {:reply, hd(result), %{state | tuples: new_tuples}}
    else
      op = %{
        id: state.next_op_id,
        type: :coll_input,
        condition: :ALL_PRESENT,
        templates: [pattern],
        from: from,
        nonblocking: false
      }
      new_state = %{state | next_op_id: state.next_op_id + 1, pending: state.pending ++ [op]}
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call({:read, pattern}, from, state) do
    if exists_match?(state.tuples, pattern) do
      {result, _} = perform_op(:coll_rd, [pattern], state.tuples)
      {:reply, hd(result), state}
    else
      op = %{
        id: state.next_op_id,
        type: :coll_rd,
        condition: :ALL_PRESENT,
        templates: [pattern],
        from: from,
        nonblocking: false
      }
      new_state = %{state | next_op_id: state.next_op_id + 1, pending: state.pending ++ [op]}
      {:noreply, new_state}
    end
  end

  # -- Handle asynchronous tuple additions --

  @impl true
  def handle_cast({:out, tuple}, state) do
    new_tuples = [tuple | state.tuples]
    new_state  = %{state | tuples: new_tuples}
                  |> process_pending_ops()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  ## Internal helper functions

  # process_pending_ops checks each pending operation and, if its condition is met,
  # performs its action (removing tuples if needed, or replying with a read result).
  # It recurses until no further pending ops are ready.
  defp process_pending_ops(state) do
    {ready_ops, not_ready_ops} =
      Enum.split_with(state.pending, fn op ->
        condition_met?(state.tuples, op.templates, op.condition)
      end)

    new_state =
      Enum.reduce(ready_ops, state, fn op, acc_state ->
        case op.type do
          :coll_input ->
            {result, new_tuples} = perform_op(:coll_input, op.templates, acc_state.tuples)
            GenServer.reply(op.from, result)
            %{acc_state | tuples: new_tuples}

          :coll_rd ->
            {result, _} = perform_op(:coll_rd, op.templates, acc_state.tuples)
            GenServer.reply(op.from, result)
            acc_state

          :coll_await ->
            GenServer.reply(op.from, true)
            acc_state
        end
      end)

    if ready_ops == [] do
      %{new_state | pending: not_ready_ops}
    else
      process_pending_ops(%{new_state | pending: not_ready_ops})
    end
  end

  # perform_op carries out the requested action on the tuple space.
  # For a removal operation (:coll_input), it removes one matching tuple per template.
  # For a read operation (:coll_rd), it returns one matching tuple per template.
  defp perform_op(:coll_input, templates, tuples) do
    {result, new_tuples} =
      Enum.reduce(templates, {[], tuples}, fn template, {acc, ts} ->
        case pop_match(ts, template) do
          {nil, remaining} ->
            {acc ++ [nil], remaining}
          {found, remaining} ->
            {acc ++ [found], remaining}
        end
      end)
    {result, new_tuples}
  end

  defp perform_op(:coll_rd, templates, tuples) do
    result =
      Enum.map(templates, fn template ->
        find_match(tuples, template)
      end)
    {result, tuples}
  end

  # pop_match removes the first tuple from the list that matches the given template.
  defp pop_match(tuples, template) do
    do_pop_match(tuples, template, [])
  end

  defp do_pop_match([], _template, acc), do: {nil, Enum.reverse(acc)}
  defp do_pop_match([h | t], template, acc) do
    if match_tuple?(template, h) do
      {h, Enum.reverse(acc) ++ t}
    else
      do_pop_match(t, template, [h | acc])
    end
  end

  # find_match returns the first tuple in the list that matches the template.
  defp find_match(tuples, template) do
    Enum.find(tuples, fn t -> match_tuple?(template, t) end)
  end

  # exists_match? returns true if at least one tuple in the list matches the template.
  defp exists_match?(tuples, template) do
    Enum.any?(tuples, fn t -> match_tuple?(template, t) end)
  end

  # match_tuple? checks whether a tuple `tuple` matches a tuple pattern `pattern`.
  # A pattern element equal to "*" or :_ is considered a wildcard.
  defp match_tuple?(pattern, tuple) when tuple_size(pattern) == tuple_size(tuple) do
    pattern
    |> Tuple.to_list()
    |> Enum.zip(Tuple.to_list(tuple))
    |> Enum.all?(fn {p, v} -> p == "*" or p == :_ or p == v end)
  end

  defp match_tuple?(_, _), do: false

  # condition_met? checks the four possible conditions given the current tuple space.
  defp condition_met?(tuples, templates, :ALL_PRESENT) do
    Enum.all?(templates, fn pat -> exists_match?(tuples, pat) end)
  end

  defp condition_met?(tuples, templates, :NOT_ALL_PRESENT) do
    Enum.any?(templates, fn pat -> not exists_match?(tuples, pat) end)
  end

  defp condition_met?(tuples, templates, :ALL_ABSENT) do
    Enum.all?(templates, fn pat -> not exists_match?(tuples, pat) end)
  end

  defp condition_met?(tuples, templates, :NOT_ALL_ABSENT) do
    Enum.any?(templates, fn pat -> exists_match?(tuples, pat) end)
  end
end
