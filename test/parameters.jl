using Base.Test
using Distributions
using Lora

fields = (
  :pdf,
  :setpdf,
  :loglikelihood,
  :logprior,
  :logtarget,
  :gradloglikelihood,
  :gradlogprior,
  :gradlogtarget,
  :tensorloglikelihood,
  :tensorlogprior,
  :tensorlogtarget,
  :dtensorloglikelihood,
  :dtensorlogprior,
  :dtensorlogtarget,
  :uptogradlogtarget,
  :uptotensorlogtarget,
  :uptodtensorlogtarget,
  :rand
)

println("    Testing ContinuousUnivariateParameter constructors...")

# Univariate parameter initialized by setting only its index and key

p = ContinuousUnivariateParameter(1, :p)
for field in fields
  @test getfield(p, field) == nothing
end

# Univariate parameter initialized via its pdf field

v = 5.18
pstate = ContinuousUnivariateParameterState(v)
nstates = Dict{Symbol, VariableState}()
μ = 6.11
nstates[:μ] = UnivariateGenericVariableState(μ)

p = ContinuousUnivariateParameter(1, :p, pdf=Normal(nstates[:μ].value))

p.pdf == Normal(μ)
lt, glt = logpdf(Normal(μ), v), gradlogpdf(Normal(μ), v)
@test p.logtarget(pstate, nstates) == lt
@test p.gradlogtarget(pstate, nstates) == glt
@test p.uptogradlogtarget(pstate, nstates) == (lt, glt)
s = Float64[p.rand(pstate, nstates) for i = 1:1000]
@test nstates[:μ].value-1 <= mean(s) <= nstates[:μ].value+1

for i in [2, 3, 4, 6, 7, 9:14, 16, 17]
  @test getfield(p, fields[i]) == nothing
end

v = -11.87
pstate.value = v
μ = -20.2
nstates[:μ].value = μ

p.pdf = Normal(nstates[:μ].value)

p.pdf == Normal(μ)
lt, glt = logpdf(Normal(μ), v), gradlogpdf(Normal(μ), v)
@test p.logtarget(pstate, nstates) == lt
@test p.gradlogtarget(pstate, nstates) == glt
@test p.uptogradlogtarget(pstate, nstates) == (lt, glt)
s = Float64[p.rand(pstate, nstates) for i = 1:1000]
@test nstates[:μ].value-1 <= mean(s) <= nstates[:μ].value+1

for i in [2, 3, 4, 6, 7, 9:14, 16, 17]
  @test getfield(p, fields[i]) == nothing
end

# Univariate parameter initialized via its setpdf field

v = 3.79
pstate = ContinuousUnivariateParameterState(v)
nstates = Dict{Symbol, VariableState}()
μ = 5.4
nstates[:μ] = UnivariateGenericVariableState(μ)

p = ContinuousUnivariateParameter(1, :p, setpdf=(pstates, nstates) -> Normal(nstates[:μ].value))

p.setpdf(pstate, nstates)
p.pdf == Normal(μ)
lt, glt = logpdf(Normal(μ), v), gradlogpdf(Normal(μ), v)
@test p.logtarget(pstate, nstates) == lt
@test p.gradlogtarget(pstate, nstates) == glt
@test p.uptogradlogtarget(pstate, nstates) == (lt, glt)
s = Float64[p.rand(pstate, nstates) for i = 1:1000]
@test nstates[:μ].value-1 <= mean(s) <= nstates[:μ].value+1

for i in [3, 4, 6, 7, 9:14, 16, 17]
  @test getfield(p, fields[i]) == nothing
end

v = -1.91
pstate.value = v
μ = 0.12
nstates[:μ].value = μ

p.setpdf(pstate, nstates)

p.pdf == Normal(μ)
lt, glt = logpdf(Normal(μ), v), gradlogpdf(Normal(μ), v)
@test p.logtarget(pstate, nstates) == lt
@test p.gradlogtarget(pstate, nstates) == glt
@test p.uptogradlogtarget(pstate, nstates) == (lt, glt)
s = Float64[p.rand(pstate, nstates) for i = 1:1000]
@test nstates[:μ].value-1 <= mean(s) <= nstates[:μ].value+1

for i in [3, 4, 6, 7, 9:14, 16, 17]
  @test getfield(p, fields[i]) == nothing
end

println("    Testing ContinuousMultivariateParameter constructors...")

ContinuousMultivariateParameter(1, :p)
ContinuousMultivariateParameter(1, :p, pdf=MvNormal(ones(2)))
