defmodule LindaTest do
  use ExUnit.Case

  setup do
    # Start a fresh Linda server for each test.
    {:ok, _pid} = Linda.start_link()
    on_exit(fn ->
      # If the server is still alive, stop it.
      if Process.whereis(Linda), do: GenServer.stop(Linda)
    end)
    :ok
  end

  @doc """
  Test that `input/1` blocks until a matching tuple is available.

  A task calling `Linda.input({"block_input", 1})` should remain blocked until
  the tuple is output via `Linda.output/1`.
  """
  test "input/1 blocks until tuple available" do
    task = Task.async(fn -> Linda.input({"block_input", 1}) end)

    # Assert that after 100ms the task is still blocked.
    assert Task.yield(task, 100) == nil

    # Output the tuple so that the blocked call can proceed.
    Linda.output({"block_input", 1})

    result = Task.await(task, 500)
    # Accept either a bare tuple or a one-element list.
    case result do
      [{"block_input", 1}] -> :ok
      {"block_input", 1} -> :ok
      other -> flunk("Unexpected result: #{inspect(other)}")
    end
  end

  @doc """
  Test that `read/1` blocks until a matching tuple is available.

  A task calling `Linda.read({"block_read", 2})` should remain blocked until
  the tuple is output via `Linda.output/1`.
  """
  test "read/1 blocks until tuple available" do
    task = Task.async(fn -> Linda.read({"block_read", 2}) end)
    assert Task.yield(task, 100) == nil

    Linda.output({"block_read", 2})
    result = Task.await(task, 500)
    case result do
      [{"block_read", 2}] -> :ok
      {"block_read", 2} -> :ok
      other -> flunk("Unexpected result: #{inspect(other)}")
    end
  end

  @doc """
  Test that `coll_input/2` (collective removal) blocks until all required tuples are available.

  In this test the operation waits for both tuples `{"ci", 1}` and `{"ci", 2}`.
  """
  test "coll_input/2 blocks until all required tuples are available" do
    task =
      Task.async(fn ->
        Linda.coll_input([{"ci", 1}, {"ci", 2}], :ALL_PRESENT)
      end)

    # With no tuples in the space, the task should remain blocked.
    assert Task.yield(task, 100) == nil

    # Output one tuple; still not enough to satisfy ALL_PRESENT.
    Linda.output({"ci", 1})
    assert Task.yield(task, 100) == nil

    # Now output the second tuple.
    Linda.output({"ci", 2})
    result = Task.await(task, 500)
    # coll_input returns a list of removed tuples.
    assert Enum.sort(result) == Enum.sort([{"ci", 1}, {"ci", 2}])
  end

  @doc """
  Test that `coll_read/2` (collective read) blocks until all required tuples are available.

  In this test the operation waits for both tuples `{"cr", 1}` and `{"cr", 2}`.
  """
  test "coll_read/2 blocks until all required tuples are available" do
    task =
      Task.async(fn ->
        Linda.coll_read([{"cr", 1}, {"cr", 2}], :ALL_PRESENT)
      end)

    assert Task.yield(task, 100) == nil

    Linda.output({"cr", 1})
    assert Task.yield(task, 100) == nil

    Linda.output({"cr", 2})
    result = Task.await(task, 500)
    # coll_read returns a list of matching tuples.
    assert Enum.sort(result) == Enum.sort([{"cr", 1}, {"cr", 2}])
  end

  @doc """
  Test that `coll_await/2` (collective await on absence) blocks until the specified tuple is absent.

  In this test we first output a tuple so that the absence condition is false.
  Then we call coll_await (which blocks), remove the tuple (via `input/1`), and finally
  trigger a re-check by outputting a dummy tuple.
  """
  test "coll_await/2 blocks until absence condition is met" do
    # Output a tuple so that the absence condition (:ALL_ABSENT) is initially false.
    Linda.output({"await", "test"})

    task =
      Task.async(fn ->
        Linda.coll_await([{"await", "test"}], :ALL_ABSENT)
      end)

    assert Task.yield(task, 100) == nil

    # Remove the tuple. (input/1 may return the removed tuple either directly or in a list.)
    removed = Linda.input({"await", "test"})
    case removed do
      [{"await", "test"}] -> :ok
      {"await", "test"} -> :ok
      other -> flunk("Unexpected removal result: #{inspect(other)}")
    end

    # Trigger pending-op processing by sending a dummy tuple.
    Linda.output({"dummy", :trigger})

    # Now coll_await should unblock.
    assert true == Task.await(task, 500)
  end
end
