--!strict
-- CatchCinematic.Types -- shared types for the framework and the cut modules.
export type CinematicPayload = {
	UserId: number, BrainrotName: string, Rarity: string, RarityColor: Color3,
	Mutation: string?, Size: string?, Cut: string?,
	RockId: string?, RockColor: Color3?, Seed: number,
	EndPos: Vector3, SurfaceY: number, TotalTime: number, NContacts: number, SegTime: number,
}

-- Private per-play state bag. Loose on purpose: the framework fills the shared
-- fields (see Takeover's RUN FIELDS header) and a cut may add its own.
export type Run = { [string]: any }

export type Beat = { name: string, t0: number, t1: number }

export type BeatHandlers = {
	enter: ((Run) -> ())?,
	update: ((Run, number) -> ())?,   -- p = 0..1 progress through the beat
	exit: ((Run) -> ())?,
}

export type Cut = {
	name: string,
	beats: { Beat },                       -- cinematic seconds; t=0 = final skip / hook-set
	handlers: { [string]: BeatHandlers },  -- keyed by beat name
	revealBeat: string,                    -- the clock parks before this beat until the grant lands
	skippable: boolean,
	skipTo: string?,                       -- beat a skip jumps to (required when skippable)
	onSkip: ((Run) -> ())?,                -- force the end-state of the skipped beats
	onCancel: ((Run) -> ())?,              -- tear down cut-built rigs on a grant that never came
	everyFrame: ((Run) -> ())?,            -- runs each frame before beat dispatch (pure in run.t)
	build: (Run) -> boolean,               -- construct cut rigs into run.stage; false = decline
	bannerText: string,
}

return {}
