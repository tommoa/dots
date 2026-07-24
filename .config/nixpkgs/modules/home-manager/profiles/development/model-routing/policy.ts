/**
 * Adding a model
 *
 * 1. Add one entry to `models` in the order it should appear in generated
 *    guidance. Use the provider's stable model ID as `id` and a human-readable
 *    `name`.
 * 2. Add every spelling used by benchmark sources to `benchmarkAliases`.
 *    The canonical `id` is already treated as an alias. Do not use fuzzy
 *    matching: aliases make model identity changes explicit and reviewable.
 * 3. Fill every manual policy field. `capabilities` contains fallback scores;
 *    also set cost, work/personal eligibility, speed, work pricing adjustment,
 *    and reasoning-effort recommendations.
 * 4. Run `./update-nix --none --model-benchmarks` so existing benchmark rows
 *    are remapped to the new model. The refresh overwrites snapshot edits and
 *    performs the normal detected Nix rebuild afterward.
 * 5. Do not edit generated regions in context.md. They remain blank in source
 *    and are populated from policy and snapshots during the Nix build.
 * 6. Run the model-routing tests. A model is selectable only after it has a
 *    policy entry; an unknown benchmark row only affects percentile ranks.
 *
 * Adding another benchmark source is separate work: extend `BenchmarkSource`,
 * add its normalized snapshot and generator adapter, include it in the Nix
 * generation derivation and pseudo-input refresh, then add its weight to the
 * relevant `benchmarkMappings` entry. Manual and source weights for each task
 * must sum to one. Missing model coverage gives that source's weight back to
 * the manual capability score.
 */
export const taskTypes = [
	"exploration",
	"research",
	"investigation",
	"implementation",
	"review",
	"architecture",
	"design",
	"writing",
	"synthesis",
] as const;

export type TaskType = (typeof taskTypes)[number];
export type Profile = "work" | "personal";
export type BenchmarkSource = "deepswe-v1.1" | "terminal-bench-2.1";

export interface BenchmarkMapping {
	manualWeight: number;
	sources: {
		source: BenchmarkSource;
		weight: number;
	}[];
}

interface ProfilePolicy {
	eligible: boolean;
}

export interface ModelPolicy {
	id: string;
	name: string;
	// Include every spelling used by checked-in benchmark sources.
	benchmarkAliases: string[];
	// Reviewed fallback values. Benchmarks currently replace implementation and
	// investigation when a matching model row exists.
	capabilities: Record<TaskType, number>;
	// Cost, speed, eligibility, and effort remain manually maintained policy.
	cost: number;
	profiles: Record<Profile, ProfilePolicy>;
	speed: number;
	workPriceMultiplier: number;
	effort: {
		routine: string;
		difficult: string;
		extreme: string;
	};
}

// Weights are overall contributions and must sum to one per capability. Add
// further sources to the array rather than combining benchmark data upstream.
export const benchmarkMappings = {
	implementation: {
		manualWeight: 0.3,
		sources: [{ source: "deepswe-v1.1", weight: 0.7 }],
	},
	investigation: {
		manualWeight: 0.65,
		sources: [{ source: "terminal-bench-2.1", weight: 0.35 }],
	},
} satisfies Partial<Record<TaskType, BenchmarkMapping>>;

export const models: ModelPolicy[] = [
	{
		id: "gpt-5.6-sol",
		name: "GPT-5.6 Sol",
		benchmarkAliases: ["gpt-5-6-sol"],
		capabilities: {
			exploration: 5,
			research: 5,
			investigation: 5,
			implementation: 5,
			review: 4,
			architecture: 5,
			design: 4,
			writing: 4,
			synthesis: 5,
		},
		cost: 5,
		profiles: {
			work: { eligible: true },
			personal: { eligible: true },
		},
		speed: 3,
		workPriceMultiplier: 0.5,
		effort: {
			routine: "medium",
			difficult: "high or extra high",
			extreme: "max only when its small marginal gain justifies the additional cost",
		},
	},
	{
		id: "gpt-5.6-terra",
		name: "GPT-5.6 Terra",
		benchmarkAliases: ["gpt-5-6-terra"],
		capabilities: {
			exploration: 5,
			research: 4,
			investigation: 5,
			implementation: 5,
			review: 4,
			architecture: 4,
			design: 4,
			writing: 4,
			synthesis: 4,
		},
		cost: 4,
		profiles: {
			work: { eligible: true },
			personal: { eligible: true },
		},
		speed: 4,
		workPriceMultiplier: 0.5,
		effort: {
			routine: "medium or high",
			difficult: "extra high",
			extreme: "max when its substantial long-horizon improvement justifies more than doubling cost",
		},
	},
	{
		id: "gpt-5.6-luna",
		name: "GPT-5.6 Luna",
		benchmarkAliases: ["gpt-5-6-luna"],
		capabilities: {
			exploration: 5,
			research: 3,
			investigation: 4,
			implementation: 5,
			review: 3,
			architecture: 3,
			design: 3,
			writing: 3,
			synthesis: 3,
		},
		cost: 2,
		profiles: {
			work: { eligible: true },
			personal: { eligible: true },
		},
		speed: 5,
		workPriceMultiplier: 0.5,
		effort: {
			routine: "low or medium for bounded work; at least high for long-horizon implementation",
			difficult: "high or extra high",
			extreme: "max is a cost-effective option for difficult long-horizon implementation",
		},
	},
	{
		id: "gpt-5.5",
		name: "GPT-5.5",
		benchmarkAliases: ["gpt-5-5"],
		capabilities: {
			exploration: 4,
			research: 5,
			investigation: 5,
			implementation: 5,
			review: 4,
			architecture: 4,
			design: 4,
			writing: 4,
			synthesis: 5,
		},
		cost: 4,
		profiles: {
			work: { eligible: true },
			personal: { eligible: false },
		},
		speed: 3,
		workPriceMultiplier: 0.5,
		effort: {
			routine: "low for basic work; medium for substantial implementation",
			difficult: "high",
			extreme: "extra high",
		},
	},
	{
		id: "claude-opus-4.7",
		name: "Claude Opus 4.7",
		benchmarkAliases: ["claude-opus-4-7"],
		capabilities: {
			exploration: 5,
			research: 4,
			investigation: 5,
			implementation: 4,
			review: 4,
			architecture: 5,
			design: 5,
			writing: 5,
			synthesis: 5,
		},
		cost: 5,
		profiles: {
			work: { eligible: true },
			personal: { eligible: true },
		},
		speed: 2,
		workPriceMultiplier: 1,
		effort: {
			routine: "medium",
			difficult: "high or extra high",
			extreme: "max for exceptionally difficult long-horizon implementation",
		},
	},
	{
		id: "claude-sonnet-4.6",
		name: "Claude Sonnet 4.6",
		benchmarkAliases: ["claude-sonnet-4-6"],
		capabilities: {
			exploration: 4,
			research: 4,
			investigation: 4,
			implementation: 3,
			review: 4,
			architecture: 4,
			design: 5,
			writing: 5,
			synthesis: 4,
		},
		cost: 3,
		profiles: {
			work: { eligible: true },
			personal: { eligible: true },
		},
		speed: 4,
		workPriceMultiplier: 1,
		effort: {
			routine: "normal or high",
			difficult: "high, or escalate to Opus",
			extreme: "prefer Opus",
		},
	},
	{
		id: "claude-haiku-4.5",
		name: "Claude Haiku 4.5",
		benchmarkAliases: [],
		capabilities: {
			exploration: 3,
			research: 2,
			investigation: 2,
			implementation: 1,
			review: 3,
			architecture: 2,
			design: 3,
			writing: 4,
			synthesis: 3,
		},
		cost: 1,
		profiles: {
			work: { eligible: true },
			personal: { eligible: true },
		},
		speed: 5,
		workPriceMultiplier: 1,
		effort: {
			routine: "no adaptive effort selection",
			difficult: "prefer Sonnet",
			extreme: "prefer Opus",
		},
	},
];

export const modelByID = new Map(models.map((model) => [model.id, model]));
export const modelByBenchmarkAlias = new Map(models.flatMap((model) => [model.id, ...model.benchmarkAliases].map((alias) => [alias, model] as const)));
