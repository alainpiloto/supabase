import { PG_META_URL } from 'lib/constants/index'
import { constructHeaders } from '../apiHelpers'
import { PgMetaDatabaseError, databaseErrorSchema, WrappedResult } from './types'
import { assertSelfHosted, encryptString, getConnectionString } from './util'

export type QueryOptions = {
  query: string
  parameters?: unknown[]
  readOnly?: boolean
  headers?: HeadersInit
}

function toNonEmptyString(value: unknown): string | undefined {
  if (typeof value === 'string' && value.trim().length > 0) return value
  return undefined
}

function stringifyErrorPayload(value: unknown): string | undefined {
  if (value === null || value === undefined) return undefined
  if (typeof value === 'string') return value
  try {
    return JSON.stringify(value)
  } catch {
    return String(value)
  }
}

function normalizePgMetaErrorPayload(result: unknown, response: Response) {
  const parsed = databaseErrorSchema.safeParse(result)
  if (parsed.success) return parsed.data

  const payload = result as Record<string, unknown> | null
  const message =
    toNonEmptyString(payload?.message) ??
    toNonEmptyString(payload?.error) ??
    toNonEmptyString(payload?.msg) ??
    toNonEmptyString(response.statusText) ??
    `Request failed with status ${response.status}`

  const formattedError =
    toNonEmptyString(payload?.formattedError) ?? stringifyErrorPayload(result) ?? message

  const code =
    toNonEmptyString(payload?.code) ??
    (typeof payload?.code === 'number' ? String(payload.code) : undefined) ??
    String(response.status)

  return { message, code, formattedError }
}

/**
 * Executes a SQL query against the self-hosted Postgres instance via pg-meta service.
 *
 * _Only call this from server-side self-hosted code._
 */
export async function executeQuery<T = unknown>({
  query,
  parameters,
  readOnly = false,
  headers,
}: QueryOptions): Promise<WrappedResult<T[]>> {
  assertSelfHosted()

  const connectionString = getConnectionString({ readOnly })
  const connectionStringEncrypted = encryptString(connectionString)

  const requestBody: { query: string; parameters?: unknown[] } = { query }
  if (parameters !== undefined) {
    requestBody.parameters = parameters
  }

  const response = await fetch(`${PG_META_URL}/query`, {
    method: 'POST',
    headers: constructHeaders({
      ...headers,
      'Content-Type': 'application/json',
      'x-connection-encrypted': connectionStringEncrypted,
    }),
    body: JSON.stringify(requestBody),
  })

  try {
    const result = await response.json()

    if (!response.ok) {
      const { message, code, formattedError } = normalizePgMetaErrorPayload(result, response)
      const error = new PgMetaDatabaseError(message, code, response.status, formattedError)
      return { data: undefined, error }
    }

    return { data: result, error: undefined }
  } catch (error) {
    if (error instanceof Error) {
      return { data: undefined, error }
    }
    throw error
  }
}
