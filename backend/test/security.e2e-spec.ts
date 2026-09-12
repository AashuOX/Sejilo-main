import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Security (e2e, STEP 27)', () => {
  let app: INestApplication;
  let alice: string;
  let bob: string;

  const stamp = Date.now();

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true }),
    );
    await app.init();

    const a = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `sec27a_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `sec27a_${stamp}`,
        displayName: 'A',
      })
      .expect(201);
    alice = a.body.token;

    const b = await request(app.getHttpServer())
      .post('/v1/users')
      .send({
        email: `sec27b_${stamp}@test.local`,
        password: 'Str0ngPass!2026',
        username: `sec27b_${stamp}`,
        displayName: 'B',
      })
      .expect(201);
    bob = b.body.token;
  });

  afterAll(async () => {
    await app.close();
  });

  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  it('IDOR: user cannot delete another user’s post (403)', async () => {
    const post = await request(app.getHttpServer())
      .post('/v1/posts')
      .set(auth(alice))
      .send({
        caption: 'alice secret post',
        media: { mimeType: 'image/jpeg', data: 'dGVzdA==' },
      })
      .expect(201);
    const postId = post.body.id as string;

    // bob tries to delete alice's post
    await request(app.getHttpServer())
      .delete(`/v1/posts/${postId}`)
      .set(auth(bob))
      .expect(403);

    // owner can delete
    await request(app.getHttpServer())
      .delete(`/v1/posts/${postId}`)
      .set(auth(alice))
      .expect(204);
  });

  it('IDOR: user cannot delete another user’s comment (403)', async () => {
    const post = await request(app.getHttpServer())
      .post('/v1/posts')
      .set(auth(alice))
      .send({
        caption: 'post for comment',
        media: { mimeType: 'image/jpeg', data: 'dGVzdA==' },
      })
      .expect(201);
    const postId = post.body.id as string;

    const comment = await request(app.getHttpServer())
      .post(`/v1/posts/${postId}/comments`)
      .set(auth(alice))
      .send({ text: 'alice comment' })
      .expect(201);
    const commentId = comment.body.id as string;

    await request(app.getHttpServer())
      .delete(`/v1/comments/${commentId}`)
      .set(auth(bob))
      .expect(403);
  });

  it('rate limiting: rapid requests to /health eventually return 429', async () => {
    let saw429 = false;
    for (let i = 0; i < 200; i++) {
      const res = await request(app.getHttpServer()).get('/health');
      if (res.status === 429) {
        saw429 = true;
        break;
      }
    }
    expect(saw429).toBe(true);
  });
});
