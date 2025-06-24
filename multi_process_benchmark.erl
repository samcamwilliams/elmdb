%%-------------------------------------------------------------------
%% This file is part of Elmdb - Erlang Lightning MDB API
%%
%% Multi-Process Mega Benchmark
%% Tests massive concurrency with 44 processes performing 10M+ operations
%%
%% Copyright (c) 2024. All rights reserved.
%%-------------------------------------------------------------------

-module(multi_process_benchmark).

%%====================================================================
%% EXPORTS
%%====================================================================
-export([
    run/0,
    mega_stress_test/0
]).

%% Worker process exports
-export([
    writer_worker/5,
    reader_worker/5,
    lister_worker/6
]).

%%====================================================================
%% PUBLIC API
%%====================================================================

%% @doc Run the complete multi-process mega benchmark
-spec run() -> ok.
run() ->
    io:format("~n=== MULTI-PROCESS MEGA BENCHMARK ===~n"),
    io:format("Testing: Multiple writers + readers + listers for 10M operations~n"),
    io:format("~s~n", [string:chars($=, 80)]),
    
    mega_stress_test(),
    
    io:format("~n=== MULTI-PROCESS MEGA BENCHMARK COMPLETED ===~n").

%% @doc Execute the main multi-process stress test with 44 concurrent processes
-spec mega_stress_test() -> map().
mega_stress_test() ->
    io:format("~n--- Multi-Process Stress Test ---~n"),
    TestDir = "bench/mega_stress",
    cleanup_test_dir(TestDir),
    
    % Setup high-performance environment for 10M operations
    MegaFlags = [
        {max_dbs, 20},              % Multiple databases if needed
        {map_size, 21474836480},    % 20GB memory map for 10M+ operations
        no_read_ahead,              % Optimized for random access
        no_sync,                    % Maximum write performance
        no_meta_sync,               % Skip metadata sync
        no_tls                      % Allow cross-thread transactions
    ],
    
    {ok, Env} = elmdb:env_open(TestDir, MegaFlags),
    {ok, Dbi} = elmdb:db_open(Env, [create]),
    
    % Pre-populate with 1M base records for initial reading/listing
    io:format("  Pre-populating database with 1M base records...~n"),
    populate_initial_data(Dbi, 1000000),
    
    Parent = self(),
    
    % Configuration for multi-process test - 10M operations
    NumWriterProcesses = 16,        % 16 concurrent writers
    NumReaderProcesses = 20,        % 20 concurrent readers  
    NumListerProcesses = 8,         % 8 concurrent listers
    
    RecordsPerWriter = 250000,      % Each writer does 250k = 4M total writes
    ReadsPerReader = 250000,        % Each reader does 250k = 5M total reads
    PassesPerLister = 5,            % Each lister does 5 full passes
    
    TotalTargetWrites = NumWriterProcesses * RecordsPerWriter,
    TotalTargetReads = NumReaderProcesses * ReadsPerReader,
    
    io:format("  Starting multi-process operations:~n"),
    io:format("    - ~p writer processes (~p records each = ~p total writes)~n",
              [NumWriterProcesses, RecordsPerWriter, TotalTargetWrites]),
    io:format("    - ~p reader processes (~p reads each = ~p total reads)~n", 
              [NumReaderProcesses, ReadsPerReader, TotalTargetReads]),
    io:format("    - ~p lister processes (~p passes each)~n",
              [NumListerProcesses, PassesPerLister]),
    
    StartTime = erlang:monotonic_time(millisecond),
    
    % Start all writer processes
    WriterPids = lists:map(fun(WriterID) ->
        spawn_link(?MODULE, writer_worker, [Parent, Dbi, WriterID, RecordsPerWriter, "mega"])
    end, lists:seq(1, NumWriterProcesses)),
    
    % Start all reader processes  
    ReaderPids = lists:map(fun(ReaderID) ->
        spawn_link(?MODULE, reader_worker, [Parent, Dbi, ReaderID, ReadsPerReader, mega_random])
    end, lists:seq(1, NumReaderProcesses)),
    
    % Start all lister processes
    ListerPids = lists:map(fun(ListerID) ->
        spawn_link(?MODULE, lister_worker, [Parent, Env, Dbi, ListerID, PassesPerLister, random_sample])
    end, lists:seq(1, NumListerProcesses)),
    
    AllPids = WriterPids ++ ReaderPids ++ ListerPids,
    TotalProcesses = length(AllPids),
    
    io:format("  Waiting for ~p processes to complete...~n", [TotalProcesses]),
    
    % Collect all results with generous timeout (10 minutes)
    Results = collect_all_results(AllPids, 600000),
    
    EndTime = erlang:monotonic_time(millisecond),
    TotalWallClock = EndTime - StartTime,
    
    % Analyze results
    {WriterResults, ReaderResults, ListerResults} = categorize_results(Results),
    
    % Calculate totals
    TotalWrites = lists:sum([Count || {Count, _Duration} <- WriterResults]),
    TotalReads = lists:sum([Count || {Count, _Duration} <- ReaderResults]), 
    TotalListOps = lists:sum([Count || {Count, _Duration} <- ListerResults]),
    TotalOperations = TotalWrites + TotalReads + TotalListOps,
    
    % Calculate average performance per process type
    AvgWriteOps = calculate_average_ops_per_sec(WriterResults),
    AvgReadOps = calculate_average_ops_per_sec(ReaderResults),
    AvgListOps = calculate_average_ops_per_sec(ListerResults),
    
    CombinedThroughput = TotalOperations * 1000 / TotalWallClock,
    
    % Display comprehensive results
    io:format("~n  === MULTI-PROCESS MEGA STRESS RESULTS ===~n"),
    io:format("  Wall Clock Time: ~p ms (~.2f seconds)~n", [TotalWallClock, TotalWallClock/1000]),
    
    io:format("~n  Process Performance Summary:~n"),
    io:format("    Writers: ~p processes, ~p total ops, avg ~.2f ops/sec per process~n",
              [NumWriterProcesses, TotalWrites, AvgWriteOps]),
    io:format("    Readers: ~p processes, ~p total ops, avg ~.2f ops/sec per process~n", 
              [NumReaderProcesses, TotalReads, AvgReadOps]),
    io:format("    Listers: ~p processes, ~p total ops, avg ~.2f ops/sec per process~n",
              [NumListerProcesses, TotalListOps, AvgListOps]),
    
    io:format("~n  Aggregate Performance:~n"),
    io:format("    Total operations: ~p~n", [TotalOperations]),
    io:format("    Combined throughput: ~.2f ops/sec~n", [CombinedThroughput]),
    io:format("    Write throughput: ~.2f ops/sec~n", [TotalWrites * 1000 / TotalWallClock]),
    io:format("    Read throughput: ~.2f ops/sec~n", [TotalReads * 1000 / TotalWallClock]),
    io:format("    List throughput: ~.2f ops/sec~n", [TotalListOps * 1000 / TotalWallClock]),
    
    % Multi-process efficiency analysis
    analyze_multi_process_performance(NumWriterProcesses, NumReaderProcesses, NumListerProcesses,
                                    AvgWriteOps, AvgReadOps, AvgListOps, TotalWallClock),
    
    % Performance scaling analysis
    analyze_scaling_characteristics(TotalOperations, CombinedThroughput, TotalProcesses),
    
    ok = elmdb:env_close(Env),
    cleanup_test_dir(TestDir),
    
    #{
        total_processes => TotalProcesses,
        total_operations => TotalOperations,
        wall_clock_ms => TotalWallClock,
        combined_throughput => CombinedThroughput,
        write_throughput => TotalWrites * 1000 / TotalWallClock,
        read_throughput => TotalReads * 1000 / TotalWallClock,
        list_throughput => TotalListOps * 1000 / TotalWallClock,
        avg_write_ops_per_process => AvgWriteOps,
        avg_read_ops_per_process => AvgReadOps,
        avg_list_ops_per_process => AvgListOps
    }.

%%====================================================================
%% WORKER PROCESSES
%%====================================================================

%% @doc Writer worker process - performs bulk writes with unique key ranges
-spec writer_worker(pid(), term(), integer(), integer(), string()) -> ok.
writer_worker(Parent, Dbi, WriterID, NumWrites, Prefix) ->
    io:format("    Writer ~p started: ~p operations~n", [WriterID, NumWrites]),
    StartTime = erlang:monotonic_time(millisecond),
    
    % Each writer gets a unique key range to avoid conflicts
    BaseKeyNum = WriterID * 10000000, % 10M offset per writer
    
    WriteCount = lists:foldl(fun(N, Acc) ->
        KeyNum = BaseKeyNum + N,
        Key = list_to_binary(io_lib:format("~s_w~p_key~10..0w", [Prefix, WriterID, KeyNum])),
        Value = create_random_value(KeyNum, 200 + (N rem 300)), % Variable size 200-500 bytes
        
        case elmdb:put(Dbi, Key, Value) of
            ok -> 
                % Less frequent progress reporting for performance
                if N rem 25000 == 0 ->
                    io:format("    Writer ~p progress: ~p/~p (~.1f%%)~n", 
                              [WriterID, N, NumWrites, (N/NumWrites)*100]);
                   true -> ok
                end,
                Acc + 1;
            Error -> 
                io:format("    Writer ~p error at ~p: ~p~n", [WriterID, N, Error]),
                Acc
        end
    end, 0, lists:seq(1, NumWrites)),
    
    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,
    
    io:format("    Writer ~p completed: ~p writes in ~p ms (~.2f ops/sec)~n", 
              [WriterID, WriteCount, Duration, WriteCount * 1000 / Duration]),
    Parent ! {writer_done, self(), WriterID, WriteCount, Duration}.

%% @doc Reader worker process - performs mixed read patterns on existing data
-spec reader_worker(pid(), term(), integer(), integer(), atom()) -> ok.
reader_worker(Parent, Dbi, ReaderID, NumReads, ReadPattern) ->
    io:format("    Reader ~p started: ~p operations~n", [ReaderID, NumReads]),
    StartTime = erlang:monotonic_time(millisecond),
    
    ReadCount = lists:foldl(fun(N, Acc) ->
        % Mix of different key patterns for comprehensive testing
        Key = case ReadPattern of
            mega_random ->
                KeyType = N rem 4,
                case KeyType of
                    0 -> 
                        % Read pre-populated base data
                        KeyNum = (N rem 1000000) + 1,
                        list_to_binary(io_lib:format("key~10..0w", [KeyNum]));
                    1 ->
                        % Read from writer 1's data
                        KeyNum = 10000000 + (N rem 250000) + 1,
                        list_to_binary(io_lib:format("mega_w1_key~10..0w", [KeyNum]));
                    2 ->
                        % Read from random writer (2-16)
                        WriterID = 2 + (N rem 15),
                        KeyNum = WriterID * 10000000 + (N rem 100000) + 1,
                        list_to_binary(io_lib:format("mega_w~p_key~10..0w", [WriterID, KeyNum]));
                    _ ->
                        % Random key that might not exist
                        KeyNum = rand:uniform(100000000),
                        list_to_binary(io_lib:format("random_key~10..0w", [KeyNum]))
                end
        end,
        
        % Small random delay to simulate real-world access patterns
        if N rem 5000 == 0 -> timer:sleep(rand:uniform(3)); true -> ok end,
        
        case elmdb:get(Dbi, Key) of
            {ok, _Value} -> 
                if N rem 25000 == 0 ->
                    io:format("    Reader ~p progress: ~p/~p (~.1f%%)~n", 
                              [ReaderID, N, NumReads, (N/NumReads)*100]);
                   true -> ok
                end,
                Acc + 1;
            not_found -> 
                Acc % Don't count misses, but don't fail either
        end
    end, 0, lists:seq(1, NumReads)),
    
    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,
    
    io:format("    Reader ~p completed: ~p successful reads in ~p ms (~.2f ops/sec)~n", 
              [ReaderID, ReadCount, Duration, ReadCount * 1000 / Duration]),
    Parent ! {reader_done, self(), ReaderID, ReadCount, Duration}.

%% @doc Lister worker process - performs cursor iterations through database
-spec lister_worker(pid(), term(), term(), integer(), integer(), atom()) -> ok.
lister_worker(Parent, Env, Dbi, ListerID, NumPasses, ListPattern) ->
    io:format("    Lister ~p started: ~p passes~n", [ListerID, NumPasses]),
    StartTime = erlang:monotonic_time(millisecond),
    
    TotalListOps = lists:foldl(fun(PassNum, TotalAcc) ->
        io:format("    Lister ~p pass ~p/~p starting...~n", [ListerID, PassNum, NumPasses]),
        
        {ok, Txn} = elmdb:ro_txn_begin(Env),
        {ok, Cursor} = elmdb:ro_txn_cursor_open(Txn, Dbi),
        
        PassOps = case ListPattern of
            full_scan ->
                % Complete database scan
                cursor_full_iteration(Cursor, 0);
            random_sample ->
                % Sample-based iteration (faster for large datasets)
                cursor_sample_iteration(Cursor, 0, ListerID)
        end,
        
        ok = elmdb:ro_txn_cursor_close(Cursor),
        ok = elmdb:ro_txn_commit(Txn),
        
        io:format("    Lister ~p pass ~p completed: ~p operations~n", [ListerID, PassNum, PassOps]),
        TotalAcc + PassOps
    end, 0, lists:seq(1, NumPasses)),
    
    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,
    
    io:format("    Lister ~p completed: ~p total ops in ~p ms (~.2f ops/sec)~n", 
              [ListerID, TotalListOps, Duration, TotalListOps * 1000 / Duration]),
    Parent ! {lister_done, self(), ListerID, TotalListOps, Duration}.

%%====================================================================
%% CURSOR ITERATION FUNCTIONS
%%====================================================================

%% @doc Perform complete iteration through all records using cursor
-spec cursor_full_iteration(term(), integer()) -> integer().
cursor_full_iteration(Cursor, Count) ->
    case Count of
        0 ->
            case elmdb:ro_txn_cursor_get(Cursor, first) of
                {ok, _Key, _Value} ->
                    cursor_full_iteration(Cursor, Count + 1);
                not_found ->
                    Count
            end;
        _ ->
            case elmdb:ro_txn_cursor_get(Cursor, next) of
                {ok, _Key, _Value} ->
                    cursor_full_iteration(Cursor, Count + 1);
                not_found ->
                    Count
            end
    end.

%% @doc Perform sample-based iteration for performance with large datasets
-spec cursor_sample_iteration(term(), integer(), integer()) -> integer().
cursor_sample_iteration(Cursor, Count, ListerID) ->
    case Count of
        0 ->
            % Start at random position based on lister ID
            StartKey = list_to_binary(io_lib:format("key~10..0w", [ListerID * 125000])),
            case elmdb:ro_txn_cursor_get(Cursor, {set_range, StartKey}) of
                {ok, _Key, _Value} ->
                    cursor_sample_iteration(Cursor, Count + 1, ListerID);
                not_found ->
                    % Try from beginning if range not found
                    case elmdb:ro_txn_cursor_get(Cursor, first) of
                        {ok, _Key, _Value} ->
                            cursor_sample_iteration(Cursor, Count + 1, ListerID);
                        not_found ->
                            Count
                    end
            end;
        N when N < 100000 -> % Limit sample size for performance
            case elmdb:ro_txn_cursor_get(Cursor, next) of
                {ok, _Key, _Value} ->
                    cursor_sample_iteration(Cursor, Count + 1, ListerID);
                not_found ->
                    Count
            end;
        _ ->
            Count % Stop at sample limit
    end.

%%====================================================================
%% RESULT PROCESSING FUNCTIONS
%%====================================================================

%% @doc Collect results from all worker processes with timeout
-spec collect_all_results(list(pid()), integer()) -> list(tuple()).
collect_all_results(Pids, Timeout) ->
    lists:map(fun(Pid) ->
        receive
            {writer_done, Pid, ID, Count, Duration} -> {writer, ID, Count, Duration};
            {reader_done, Pid, ID, Count, Duration} -> {reader, ID, Count, Duration};
            {lister_done, Pid, ID, Count, Duration} -> {lister, ID, Count, Duration}
        after Timeout ->
            io:format("    Warning: Process ~p timed out~n", [Pid]),
            {timeout, Pid, 0, Timeout}
        end
    end, Pids).

%% @doc Categorize results by process type
-spec categorize_results(list(tuple())) -> {list(tuple()), list(tuple()), list(tuple())}.
categorize_results(Results) ->
    WriterResults = [{Count, Duration} || {writer, _ID, Count, Duration} <- Results],
    ReaderResults = [{Count, Duration} || {reader, _ID, Count, Duration} <- Results],
    ListerResults = [{Count, Duration} || {lister, _ID, Count, Duration} <- Results],
    {WriterResults, ReaderResults, ListerResults}.

%% @doc Calculate average operations per second across results
-spec calculate_average_ops_per_sec(list(tuple())) -> float().
calculate_average_ops_per_sec(Results) ->
    case Results of
        [] -> 0.0;
        _ ->
            OpsPerSecList = [Count * 1000 / Duration || {Count, Duration} <- Results, Duration > 0],
            case OpsPerSecList of
                [] -> 0.0;
                _ -> lists:sum(OpsPerSecList) / length(OpsPerSecList)
            end
    end.

%%====================================================================
%% ANALYSIS FUNCTIONS
%%====================================================================

%% @doc Analyze multi-process performance characteristics
-spec analyze_multi_process_performance(integer(), integer(), integer(), float(), float(), float(), integer()) -> ok.
analyze_multi_process_performance(NumWriters, NumReaders, NumListers, 
                                AvgWriteOps, AvgReadOps, AvgListOps, WallClockMs) ->
    io:format("~n  Multi-Process Performance Analysis:~n"),
    
    % Process efficiency (how well processes scale)
    io:format("    Process Scaling:~n"),
    io:format("      Writers: ~p processes @ ~.2f ops/sec each~n", [NumWriters, AvgWriteOps]),
    io:format("      Readers: ~p processes @ ~.2f ops/sec each~n", [NumReaders, AvgReadOps]),
    io:format("      Listers: ~p processes @ ~.2f ops/sec each~n", [NumListers, AvgListOps]),
    
    % Identify any process type bottlenecks
    if AvgWriteOps < 1000 ->
        io:format("    ⚠ Writer processes may be contending (avg ~.2f ops/sec)~n", [AvgWriteOps]);
       AvgReadOps < 5000 ->
        io:format("    ⚠ Reader processes slower than expected (avg ~.2f ops/sec)~n", [AvgReadOps]);
       true ->
        io:format("    ✓ All process types performing well~n")
    end,
    
    % Overall assessment
    TotalWallClockSec = WallClockMs / 1000,
    if TotalWallClockSec < 60 ->
        io:format("    ✓ Excellent: Completed 10M+ operations in ~.2f seconds~n", [TotalWallClockSec]);
       TotalWallClockSec < 120 ->
        io:format("    ✓ Good: Completed 10M+ operations in ~.2f seconds~n", [TotalWallClockSec]);
       true ->
        io:format("    ⚠ Slower than expected: ~.2f seconds for 10M+ operations~n", [TotalWallClockSec])
    end.

%% @doc Analyze scaling characteristics across all processes
-spec analyze_scaling_characteristics(integer(), float(), integer()) -> ok.
analyze_scaling_characteristics(TotalOps, Throughput, TotalProcesses) ->
    io:format("~n  Scaling Characteristics:~n"),
    
    OpsPerProcess = TotalOps / TotalProcesses,
    ThroughputPerProcess = Throughput / TotalProcesses,
    
    io:format("    Average ops per process: ~.2f~n", [OpsPerProcess]),
    io:format("    Average throughput per process: ~.2f ops/sec~n", [ThroughputPerProcess]),
    
    % Scaling efficiency assessment
    if Throughput > 500000 ->
        io:format("    ✓ Excellent scaling: ~.2f total ops/sec with ~p processes~n", 
                  [Throughput, TotalProcesses]);
       Throughput > 200000 ->
        io:format("    ✓ Good scaling: ~.2f total ops/sec with ~p processes~n",
                  [Throughput, TotalProcesses]);
       true ->
        io:format("    ⚠ Scaling could be improved: ~.2f total ops/sec with ~p processes~n", 
                  [Throughput, TotalProcesses])
    end.

%%====================================================================
%% UTILITY FUNCTIONS
%%====================================================================

%% @doc Populate database with initial data for testing
-spec populate_initial_data(term(), integer()) -> ok.
populate_initial_data(Dbi, NumRecords) ->
    lists:foreach(fun(N) ->
        if N rem 200000 == 0 ->
            io:format("    Initial data progress: ~p/~p~n", [N, NumRecords]);
           true -> ok
        end,
        Key = list_to_binary(io_lib:format("key~10..0w", [N])),
        Value = create_random_value(N, 150),
        ok = elmdb:put(Dbi, Key, Value)
    end, lists:seq(1, NumRecords)).

%% @doc Create random value with specified base size and variable content
-spec create_random_value(integer(), integer()) -> binary().
create_random_value(N, BaseSize) ->
    % Create variable-size values with some random content
    Timestamp = erlang:system_time(),
    RandomComponent = rand:uniform(1000000),
    Base = io_lib:format("val~w_ts~w_rnd~w", [N, Timestamp, RandomComponent]),
    Padding = BaseSize - length(Base),
    if 
        Padding > 0 ->
            % Add random padding characters
            PaddingChars = [65 + (rand:uniform(26) - 1) || _ <- lists:seq(1, Padding)],
            list_to_binary([Base, PaddingChars]);
        true ->
            list_to_binary(Base)
    end.

%% @doc Clean up test directory and database files
-spec cleanup_test_dir(string()) -> ok.
cleanup_test_dir(Dir) ->
    file:delete(Dir ++ "/data.mdb"),
    file:delete(Dir ++ "/lock.mdb"),
    file:del_dir(Dir).