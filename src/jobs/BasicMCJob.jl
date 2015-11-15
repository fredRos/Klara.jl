### BasicMCJob

# BasicMCJob is used for sampling a single parameter via serial Monte Carlo
# It is the most elementary and typical Markov chain Monte Carlo (MCMC) job

type BasicMCJob{S<:VariableState} <: MCJob
  model::GenericModel # Model of single parameter
  pindex::Int # Index of single parameter in model.vertices
  parameter::Parameter # Points to model.vertices[pindex] for faster access
  sampler::MCSampler
  tuner::MCTuner
  range::BasicMCRange
  vstate::Vector{S} # Vector of variable states ordered according to variables in model.vertices
  pstate::ParameterState # Points to vstate[pindex] for faster access
  sstate::MCSamplerState # Internal state of MCSampler
  output::Union{VariableNState, VariableIOStream} # Output of model's single parameter
  count::Int # Current number of post-burnin iterations
  plain::Bool # If plain=false then job flow is controlled via tasks, else it is controlled without tasks
  task::Union{Task, Void}
  resetplain!::Function
  iterate!::Function
  close::Function
  reset!::Function
  consume!::Function
  save!::Function

  function BasicMCJob(
    model::GenericModel,
    pindex::Int,
    sampler::MCSampler,
    tuner::MCTuner,
    range::BasicMCRange,
    vstate::Vector{S},
    outopts::Dict, # Options related to output
    plain::Bool,
    checkin::Bool
  )
    instance = new()

    instance.model = model
    instance.pindex = pindex
    instance.sampler = sampler
    instance.tuner = tuner
    instance.range = range
    instance.vstate = vstate
    instance.plain = plain

    if checkin
      Lora.checkin(instance)
    end

    instance.parameter = instance.model.vertices[instance.pindex]

    instance.pstate = instance.vstate[instance.pindex]
    initialize!(instance.pstate, instance.vstate, instance.parameter, sampler)

    instance.sstate = sampler_state(sampler, tuner, instance.pstate)

    augment!(outopts)
    instance.output = initialize_output(instance.pstate, range.npoststeps, outopts)

    instance.count = 0

    if outopts[:destination] == :nstate
      instance.close = () -> ()
      instance.save! = (i::Int) -> instance.output.copy(instance.pstate, i)
    elseif outopts[:destination] == :iostream
      instance.close = () -> close(instance.output)
      instance.save! = eval(codegen_save_iostream_basic_mcjob(instance, outopts))
    else
      error(":destination must be set to :nstate or :iostream or :none, got $(outopts[:destination])")
    end

    instance.resetplain! = eval(codegen_resetplain_basic_mcjob(instance))
    instance.iterate! = eval(codegen_iterate_basic_mcjob(instance, outopts))

    if plain
      instance.task = nothing
      instance.reset! = instance.resetplain!
      instance.consume! = () -> instance.iterate!(
        instance.pstate,
        instance.vstate,
        instance.sstate,
        instance.parameter,
        instance.sampler,
        instance.tuner,
        instance.range
      )
    else
      instance.task = Task(() -> initialize_task!(
        instance.pstate,
        instance.vstate,
        instance.sstate,
        instance.parameter,
        instance.sampler,
        instance.tuner,
        instance.range,
        instance.resetplain!,
        instance.iterate!
      ))
      instance.reset! = eval(codegen_reset_task_basic_mcjob(instance))
      instance.consume! = () -> consume(instance.task)
    end

    instance
  end
end

BasicMCJob{S<:VariableState}(
  model::GenericModel,
  pindex::Int,
  sampler::MCSampler,
  tuner::MCTuner,
  range::BasicMCRange,
  vstate::Vector{S},
  outopts::Dict, # Options related to output
  plain::Bool,
  checkin::Bool
) =
  BasicMCJob{S}(model, pindex, sampler, tuner, range, vstate, outopts, plain, checkin)

BasicMCJob{S<:VariableState}(
  model::GenericModel,
  sampler::MCSampler,
  range::BasicMCRange,
  vstate::Vector{S};
  pindex::Int=findfirst(v::Variable -> isa(v, Parameter), model.vertices),
  tuner::MCTuner=VanillaMCTuner(),
  outopts::Dict=Dict(:destination=>:nstate, :monitor=>[:value], :diagnostics=>Symbol[]),
  plain::Bool=true,
  checkin::Bool=false
) =
  BasicMCJob(model, pindex, sampler, tuner, range, vstate, outopts, plain, checkin)

function BasicMCJob{S<:VariableState}(
  model::GenericModel,
  sampler::MCSampler,
  range::BasicMCRange,
  vstate::Dict{Symbol, S};
  pindex::Int=findfirst(v::Variable -> isa(v, Parameter), model.vertices),
  tuner::MCTuner=VanillaMCTuner(),
  outopts::Dict=Dict(:destination=>:nstate, :monitor=>[:value], :diagnostics=>Symbol[]),
  plain::Bool=true,
  checkin::Bool=false
)
  vsvector = Array(S, length(vstate))
  for (k, v) in vstate
    vsvector[model.ofkey[k]] = v
  end

  BasicMCJob(model, pindex, sampler, tuner, range, vsvector, outopts, plain, checkin)
end

function BasicMCJob(
  model::GenericModel,
  sampler::MCSampler,
  range::BasicMCRange,
  vstate::Vector;
  pindex::Int=findfirst(v::Variable -> isa(v, Parameter), model.vertices),
  tuner::MCTuner=VanillaMCTuner(),
  outopts::Dict=Dict(:destination=>:nstate, :monitor=>[:value], :diagnostics=>Symbol[]),
  plain::Bool=true,
  checkin::Bool=false
)
  nvstate = length(vstate)
  vsvector = Array(VariableState, nvstate)
  for i in 1:nvstate
    if isa(vstate[i], VariableState)
      vsvector[i] = vstate[i]
    elseif isa(vstate[i], Number) ||
      (isa(vstate[i], Vector) && issubtype(eltype(vstate[i]), Number)) ||
      (isa(vstate[i], Matrix) && issubtype(eltype(vstate[i]), Number))
      vsvector[i] = default_state(model.vertices[i], vstate[i])
    else
      error("Variable state or state value of type $(typeof(vstate[i])) not valid")
    end
  end

  BasicMCJob(model, pindex, sampler, tuner, range, vsvector, outopts, plain, checkin)
end

function BasicMCJob(
  model::GenericModel,
  sampler::MCSampler,
  range::BasicMCRange,
  vstate::Dict;
  pindex::Int=findfirst(v::Variable -> isa(v, Parameter), model.vertices),
  tuner::MCTuner=VanillaMCTuner(),
  outopts::Dict=Dict(:destination=>:nstate, :monitor=>[:value], :diagnostics=>Symbol[]),
  plain::Bool=true,
  checkin::Bool=false
)
  vsvector = Array(Any, length(vstate))
  for (k, v) in vstate
    vsvector[model.ofkey[k]] = v
  end

  BasicMCJob(model, sampler, range, vsvector, pindex=pindex, tuner=tuner, outopts=outopts, plain=plain, checkin=checkin)
end

# It is likely that MCMC inference for parameters of ODEs will require a separate ODEBasicMCJob
# In that case the iterate!() function will take a second variable (transformation) as input argument

function codegen_save_iostream_basic_mcjob(job::BasicMCJob, outopts::Dict)
  body = []

  push!(body, :($(job).output.write($(job).pstate)))

  if outopts[:flush]
    push!(body, :($(job).output.flush()))
  end

  @gensym save_iostream_basic_mcjob

  quote
    function $save_iostream_basic_mcjob()
      $(body...)
    end
  end
end

function codegen_resetplain_basic_mcjob(job::BasicMCJob)
  body = []

  push!(body, :(reset!($(job).pstate, $(job).vstate, $(:_x), $(job).parameter, $(job).sampler)))

  if isa(job.output, VariableIOStream)
    push!(body, :($(job).output.reset()))
    push!(body, :($(job).output.mark()))
  end

  push!(body, :($(job).count = 0))

  @gensym resetplain_basic_mcjob

  if isa(job.pstate, ContinuousUnivariateParameterState) &&
    isa(job.sstate.pstate, ContinuousUnivariateParameterState) &&
    isa(job.parameter, ContinuousUnivariateParameter)
    result = quote
      function $resetplain_basic_mcjob{N<:AbstractFloat}(_x::N)
        $(body...)
      end
    end
  elseif isa(job.pstate, ContinuousMultivariateParameterState) &&
    isa(job.sstate.pstate, ContinuousMultivariateParameterState) &&
    isa(job.parameter, ContinuousMultivariateParameter)
    result = quote
      function $resetplain_basic_mcjob{N<:AbstractFloat}(_x::Vector{N})
        $(body...)
      end
    end
  end
end

function codegen_reset_task_basic_mcjob(job::BasicMCJob)
  body = []

  push!(body, :($(job).task.storage[:reset]($(:_x))))

  @gensym reset_task_basic_mcjob

  if isa(job.pstate, ContinuousUnivariateParameterState) &&
    isa(job.sstate.pstate, ContinuousUnivariateParameterState) &&
    isa(job.parameter, ContinuousUnivariateParameter)
    result = quote
      function $reset_task_basic_mcjob{N<:AbstractFloat}(_x::N)
        $(body...)
      end
    end
  elseif isa(job.pstate, ContinuousMultivariateParameterState) &&
    isa(job.sstate.pstate, ContinuousMultivariateParameterState) &&
    isa(job.parameter, ContinuousMultivariateParameter)
    result = quote
      function $reset_task_basic_mcjob{N<:AbstractFloat}(_x::Vector{N})
        $(body...)
      end
    end
  end
end

function checkin(job::BasicMCJob)
  nv = num_vertices(job.model)
  nvstate = length(job.vstate)

  if nv != nvstate
    error("Number of variables ( = $nv) not equal to number of variable states ( = $nvstate)")
  end

  pindex = find(v::Variable -> isa(v, Parameter), job.model.vertices)
  np = length(pindex)

  if np == 0 || np >= 2
    error("The model has $(np == 0 ? "no": string(np)) parameters, but a BasicMCJob requires exactly one parameter")
  else # elseif np == 1
    if pindex[1] != job.pindex
      error("Parameter located in job.model.vertices[$(pindex[1])], but job.pindex = $(job.pindex)")
    end
  end

  pstate = job.vstate[job.pindex]

  if !isa(pstate, ParameterState)
    error("The parameter's state must be saved in a ParameterState subtype, got $(typeof(pstate)) state type")
  else
    if isa(job.model.vertices[job.pindex], ContinuousParameter) && !isa(pstate, ContinuousParameterState)
      error(string(
        "The state of the continuous parameter must be saved in a ContinuousParameterState subtype, ",
        "got $(typeof(pstate))"
      ))
    end
  end
end

function Base.run(job::BasicMCJob)
  for i in 1:job.range.nsteps
    job.consume!()

    if in(i, job.range.postrange)
      job.save!(job.count+=1)
    end
  end

  job.close()

  job.output
end
