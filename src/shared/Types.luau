--!strict
--[[
	Types — tipos partilhados entre servidor e cliente.
	Nenhum valor de balanceamento vive aqui; apenas a forma dos dados.
]]

export type Team = "A" | "B"

export type TroopId = string

export type TroopDef = {
	id: TroopId,
	cost: number,
	-- combate
	hp: number,
	damage: number,
	range: number, -- studs, medido entre as bordas das hitboxes
	attackSpeed: number, -- ataques por segundo
	moveSpeed: number, -- studs por segundo
	aoeRadius: number?, -- se definido, o ataque atinge todos os inimigos no raio
	healAmount: number?, -- reservado para o healer (MVP)
	bonusVs: { [TroopId]: number }, -- multiplicador de dano contra cada tropa
	-- apresentação (o cliente desenha a partir daqui)
	radius: number,
	height: number,
	color: Color3,
}

-- Uma unidade colocada na fase de preparação (estado autoritativo do servidor).
export type ArmyEntry = {
	id: number,
	troopId: TroopId,
	x: number,
	z: number,
}

export type MatchPhase = "Lobby" | "Prep" | "Reveal" | "Battle" | "RoundEnd" | "MatchEnd"

export type RoundEndReason = "elimination" | "timeout" | "aborted"

-- Servidor -> cliente -------------------------------------------------------

export type MatchStatePayload = {
	phase: MatchPhase,
	round: number,
	maxRounds: number,
	-- Relógio sincronizado (workspace:GetServerTimeNow) para o fim da fase.
	endsAt: number,
	duration: number,
	team: Team?, -- a equipa de quem recebe; nil quando é espectador/lobby
	selfReady: boolean,
	opponentReady: boolean,
	opponentName: string?,
	selfScore: number,
	opponentScore: number,
}

export type ArmyPayload = {
	gold: number,
	maxUnits: number,
	units: { ArmyEntry },
}

export type SpawnEntry = {
	id: number,
	troopId: TroopId,
	team: Team,
	maxHp: number,
	x: number,
	z: number,
}

export type RosterPayload = {
	units: { SpawnEntry },
}

-- `alive` é um array plano [id, x, z, hp, ...] para manter o pacote pequeno.
export type SnapshotPayload = {
	tick: number,
	alive: { number },
	dead: { number },
}

export type RoundResultPayload = {
	round: number,
	winner: Team?, -- nil = empate
	reason: RoundEndReason,
	valueA: number,
	valueB: number,
	countA: number,
	countB: number,
	scoreA: number,
	scoreB: number,
}

export type MatchResultPayload = {
	winner: Team?,
	scoreA: number,
	scoreB: number,
}

export type NoticePayload = {
	key: string,
	arg: string?,
}

return {}
