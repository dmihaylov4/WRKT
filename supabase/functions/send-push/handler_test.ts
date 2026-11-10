import { strict as assert } from 'node:assert'
import { handlePushRequest } from './handler.ts'

const secret = 'server-only-fixture-secret'
const payload = { user_id: '11111111-1111-1111-1111-111111111111', title: 'Workout', body: 'A test notification' }

function request(body: unknown = payload, authorization: string | null = `Bearer ${secret}`): Request {
  const headers = new Headers({ 'content-type': 'application/json' })
  if (authorization) headers.set('authorization', authorization)
  return new Request('https://example.test/send-push', { method: 'POST', headers, body: JSON.stringify(body) })
}

Deno.test('anonymous and ordinary user credentials cannot dispatch or read recipients', async () => {
  for (const authorization of [null, 'Bearer user-jwt', secret, `Bearer ${secret}x`]) {
    const response = await handlePushRequest(request(payload, authorization), secret, () => {
      throw new Error('Unauthorized request reached delivery')
    })
    assert.equal(response.status, 401)
  }
})

Deno.test('missing server configuration fails closed', async () => {
  const response = await handlePushRequest(request(), undefined, () => {
    throw new Error('Unconfigured request reached delivery')
  })
  assert.equal(response.status, 503)
})

Deno.test('trusted dispatch preserves the validated notification', async () => {
  let calls = 0
  const response = await handlePushRequest(request(), secret, async body => {
    calls++
    assert.deepEqual(body, payload)
    return Response.json({ sent: 1 })
  })
  assert.equal(calls, 1)
  assert.equal(response.status, 200)
})

Deno.test('invalid payloads cannot reach delivery or override APNs fields', async () => {
  for (const body of [null, [], {}, { ...payload, user_id: 'invalid' }, { ...payload, badge: -1 },
    { ...payload, title: '' }, { ...payload, data: [] }, { ...payload, data: { aps: {} } }]) {
    const response = await handlePushRequest(request(body), secret, () => {
      throw new Error('Invalid payload reached delivery')
    })
    assert.equal(response.status, 400)
  }
})

Deno.test('method, content type, malformed JSON and oversized bodies are rejected', async () => {
  const inputs: [Request, number][] = [
    [new Request('https://example.test', { method: 'GET' }), 405],
    [new Request('https://example.test', { method: 'POST', headers: { authorization: `Bearer ${secret}` }, body: '{}' }), 415],
    [new Request('https://example.test', { method: 'POST', headers: { authorization: `Bearer ${secret}`, 'content-type': 'application/json' }, body: '{' }), 400],
    [request({ ...payload, body: 'x'.repeat(9000) }), 413],
  ]
  for (const [input, status] of inputs) {
    const response = await handlePushRequest(input, secret, () => {
      throw new Error('Invalid request reached delivery')
    })
    assert.equal(response.status, status)
  }
})
