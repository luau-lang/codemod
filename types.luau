export type Context<Options = { [any]: any }> = {
	path: string,
	source: string,
	options: Options,
}

export type Transformer = (Context) -> string

export type ConfigOption = {
	kind: "string",
	name: string,
	default: string?,
} | {
	kind: "boolean",
	name: string,
	default: boolean?,
}

export type Codemod = {
	options: { ConfigOption }?,
	transform: Transformer,
}

return {
	DELETION_MARKER = "$DELETION_MARKER",
}
