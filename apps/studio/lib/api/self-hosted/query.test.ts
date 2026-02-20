import { beforeEach, describe, expect, it, vi } from 'vitest'

import { executeQuery } from './query'
import { PgMetaDatabaseError } from './types'

vi.mock('lib/constants/index', () => ({
  PG_META_URL: 'http://pg-meta.test',
}))

vi.mock('../apiHelpers', () => ({
  constructHeaders: vi.fn((headers?: HeadersInit) => headers ?? {}),
}))

vi.mock('./util', () => ({
  assertSelfHosted: vi.fn(),
  encryptString: vi.fn(() => 'encrypted-connstring'),
  getConnectionString: vi.fn(() => 'postgresql://supabase_admin:postgres@db:5432/postgres'),
}))

describe('api/self-hosted/query', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('returns query data when pg-meta request succeeds', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        statusText: 'OK',
        json: async () => [{ ok: 1 }],
      } as Response)
    )

    const result = await executeQuery({ query: 'select 1 as ok' })

    expect(result.error).toBeUndefined()
    expect(result.data).toEqual([{ ok: 1 }])
  })

  it('normalizes non-standard pg-meta error payloads into PgMetaDatabaseError', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 500,
        statusText: 'Internal Server Error',
        json: async () => ({ error: 'failed to get upstream connection details' }),
      } as Response)
    )

    const result = await executeQuery({ query: 'select 1 as ok' })

    expect(result.data).toBeUndefined()
    expect(result.error).toBeInstanceOf(PgMetaDatabaseError)

    const error = result.error as PgMetaDatabaseError
    expect(error.statusCode).toBe(500)
    expect(error.code).toBe('500')
    expect(error.message).toBe('failed to get upstream connection details')
    expect(error.formattedError).toContain('failed to get upstream connection details')
  })
})
