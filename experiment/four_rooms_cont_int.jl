__precompile__(true)

module FourRoomsContIntExperiment

using Reproduce
using JLD2
using Resampling
import Resampling.ExpUtils: algorithm_settings!, build_algorithm_dict
using Resampling.ExpUtils.FourRoomsContUtil
# import JuliaRL
using Random
using Statistics
import Flux
import Flux: Descent
import ProgressMeter
import StatsBase
using JuliaRL.FeatureCreators

function mase(preds, truth, args...)
    return mean(abs.(preds .- truth))
end

function mase(model::Resampling.TabularLayer{Array{Float64, 3}}, truth, target_policy_matrix)
    # println(size(model.W))
    return @inbounds mean(abs.(sum(target_policy_matrix .* model.W; dims=1)[1,:,:]  .- truth))
end

function get_target_policy_matrix(env::FourRooms, μ::Resampling.AbstractPolicy)
    tmp = zeros(4, 11, 11)
    for state in Resampling.get_states(env)
        tmp[:, state] .= [get(μ, state, action, nothing, nothing, nothing) for action in 1:4]
    end
    return tmp
end


function exp_settings(as::ArgParseSettings = ArgParseSettings(exc_handler=Reproduce.ArgParse.debug_handler, exit_after_help=false))
    @add_arg_table as begin
        # Basic Experiment Arguments
        "--exp_loc"
        arg_type=String
        required=true
        "--seed"
        help = "Starting seed (initialize seed + run)"
        default = 0
        arg_type = Int64
        "--run"
        help = "Run"
        default = 1
        arg_type = Int64
        "--numinter"
        help = "Number of interactions"
        default = 1000
        arg_type = Int64
        "--train_gap"
        help = "Number of interactions in-between training iterations"
        default = 1
        arg_type = Int64
        "--warm_up"
        help = "number of interactions to wait to begin learning"
        default = 0
        arg_type = Int64
        "--buffersize"
        help = "Size of buffer"
        default = 15000
        arg_type = Int64
        "--batchsize"
        help = "Size of batch"
        default = 16
        arg_type = Int64
        "--eval_points"
        help="Number of points to evaluate over"
        default = 50
        arg_type = Int64
        "--eval_steps"
        help="Number of points to evaluate over"
        default = 1
        arg_type = Int64
        "--working"
        action=:store_true
        "--compress"
        action=:store_true
    end

    @add_arg_table as begin
        "--opt"
        arg_type=String
        default="Descent"
        "--alphas"
        arg_type=Float64
        nargs='+'
        required=true
        "--beta"
        help="Interpolation parameter for sample policy"
        arg_type=Float64
        required=true
    end

    @add_arg_table as begin
        "--tilings"
        arg_type=Int64
        default=64
        "--tiles"
        arg_type=Int64
        default=8
    end

    # algorithm_settings!(as)
    env_settings!(as)

    return as
end


function main_experiment(args::Vector{String})

    as = exp_settings()
    parsed = parse_args(args, as)
    if parsed == nothing
        return
    end
    save_loc=""
    if !parsed["working"]
        create_info!(parsed, parsed["exp_loc"]; filter_keys=["verbose", "working", "exp_loc"])
        save_loc = Reproduce.get_save_dir(parsed)
        if isfile(joinpath(save_loc, "results.jld2"))
            return
        end
    end

    # num_runs = parsed["numruns"]
    train_gap = parsed["train_gap"]
    warm_up = parsed["warm_up"]
    num_interactions = parsed["numinter"]
    buffer_size = parsed["buffersize"]
    batch_size = parsed["batchsize"]
    α_arr = parsed["alphas"]

    μ = get_policy(parsed)
    gvf = FourRoomsContUtil.GVFS[parsed["gvf"]]
    max_is_ratio = FourRoomsContUtil.get_max_is_ratio(μ, gvf.policy)

    sample_policy = InterpolationPolicy(parsed["beta"], μ, gvf.policy)

    rng = MersenneTwister(parsed["seed"] + parsed["run"])

    env = FourRoomsCont(0.1, 0.001)
    # eval_states = [Resampling.random_start_state(env, rng) for i in 1:parsed["eval_points"]]
    eval_states = FourRoomsContUtil.sample_according_to_dmu(env, parsed["policy"], parsed["eval_points"]; rng=rng)
    eval_rets = [mean(Resampling.MonteCarloReturn(env, gvf, start_state, 100; rng=rng)) for start_state in eval_states]
    opt = getproperty(Flux, Symbol(parsed["opt"]))()
    agent = IntFourRoomsContAgent(μ, sample_policy, gvf, opt, parsed["tilings"], parsed["tiles"], α_arr,
                                  train_gap, buffer_size, batch_size, warm_up, size(env);
                                 max_is_ratio=max_is_ratio)

    error_arr = zeros(Float32, length(α_arr), Int64(floor(num_interactions/parsed["eval_steps"])))

    _, s_t = start!(env; rng=rng)
    action = start!(agent, s_t; rng=rng)
    predict_arr = Array{Array{Float64, 1}, 1}()

    eval_step = 1

    # ProgressMeter.@showprogress 0.1 "Step: " for step in 1:num_interactions
    for step in 1:num_interactions

        # Get experience from environment.
        _, s_tp1, r, terminal = step!(env, action; rng=rng)
        action = step!(agent, s_tp1, r, terminal; rng=rng)

        # calculate error
        if (step-1)%parsed["eval_steps"] == 0
            predict!(agent, eval_states, predict_arr)
            for α_idx in eachindex(agent.α_arr)
                error_arr[α_idx, eval_step] = Float32(mase(predict_arr[α_idx], eval_rets))
            end
            eval_step += 1
        end
    end

    if parsed["working"]
        return error_arr
    else
        results = error_arr
        if parsed["compress"]
            JLD2.save(
                JLD2.FileIO.File(JLD2.FileIO.DataFormat{:JLD2},
                                 joinpath(save_loc, "results.jld2")),
                Dict("results"=>results); compress=true)
        else
            @save joinpath(save_loc, "results.jld2") results
        end
    end

end

Base.@ccallable function julia_main(ARGS::Vector{String})::Cint
    main_experiment(ARGS)
    return 0
end

end







