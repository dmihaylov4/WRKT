export interface PushRequest {
  user_id: string
  title: string
  body: string
  data?: Record<string, unknown>
  badge?: number
  sound?: string
}

const maxRequestBytes = 8192
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

async function matchesSecret(header: string | null, secret: string): Promise<boolean> {
  if (!header) return false
  const encoder = new TextEncoder()
  const [actual, expected] = await Promise.all(
    [header, `Bearer ${secret}`].map(value => crypto.subtle.digest('SHA-256', encoder.encode(value)))
  )
  const a = new Uint8Array(actual)
  const b = new Uint8Array(expected)
  let difference = 0
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i]
  return difference === 0
}

function isPushRequest(value: unknown): value is PushRequest {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false
  const request = value as Record<string, unknown>
  return typeof request.user_id === 'string' && uuid.test(request.user_id)
    && typeof request.title === 'string' && request.title.trim().length > 0 && request.title.length <= 256
    && typeof request.body === 'string' && request.body.trim().length > 0 && request.body.length <= 2048
    && (request.badge === undefined || (Number.isSafeInteger(request.badge) && (request.badge as number) >= 0))
    && (request.sound === undefined || request.sound === 'default')
    && (request.data === undefined || (
      request.data !== null && typeof request.data === 'object' && !Array.isArray(request.data)
      && !Object.hasOwn(request.data, 'aps')
    ))
}

export async function handlePushRequest(
  request: Request,
  secret: string | undefined,
  deliver: (payload: PushRequest) => Promise<Response>,
): Promise<Response> {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405, headers: { Allow: 'POST' } })
  }
  if (!secret) return Response.json({ error: 'Push dispatch unavailable' }, { status: 503 })
  if (!await matchesSecret(request.headers.get('authorization'), secret)) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 })
  }
  if (request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') {
    return Response.json({ error: 'Expected application/json' }, { status: 415 })
  }
  if (Number(request.headers.get('content-length')) > maxRequestBytes) {
    return Response.json({ error: 'Request too large' }, { status: 413 })
  }

  let payload: unknown
  try {
    const body = await request.text()
    if (new TextEncoder().encode(body).length > maxRequestBytes) {
      return Response.json({ error: 'Request too large' }, { status: 413 })
    }
    payload = JSON.parse(body)
  } catch {
    return Response.json({ error: 'Invalid JSON' }, { status: 400 })
  }
  if (!isPushRequest(payload)) return Response.json({ error: 'Invalid push payload' }, { status: 400 })
  return await deliver(payload)
}
