import { Test, TestingModule } from '@nestjs/testing';
import { SyncService } from './sync.service';
import { PrismaService } from '../prisma/prisma.service';
import { MeshRelayService } from '../mesh/mesh-relay.service';
import { FirebaseSyncService } from './firebase-sync.service';
import { WebhooksService } from '../webhooks/webhooks.service';
import { ContentVisibilityService } from '../common/content-visibility.service';

const UUID = (n: string) =>
  `${n.repeat(8)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(4)}-${n.repeat(12)}`;

const ME = UUID('a');
const THEM = UUID('b');
const CONV = UUID('c');

/// The offline queue is the second way into a conversation. `POST /v1/sync`
/// used to check membership and nothing else, so anything the send endpoint
/// refused arrived anyway by being queued and flushed.
describe('SyncService offline ingest', () => {
  let service: SyncService;
  let prisma: any;
  let visibility: { isBlockedBetween: jest.Mock };

  const pending = {
    clientMessageId: 'cm_1',
    conversationId: CONV,
    text: 'hi',
    createdAt: new Date().toISOString(),
  };

  beforeEach(async () => {
    prisma = {
      conversationMember: {
        findUnique: jest.fn().mockResolvedValue({
          conversation: {
            kind: 'direct',
            members: [{ userId: ME }, { userId: THEM }],
          },
        }),
        findMany: jest.fn().mockResolvedValue([]),
      },
      message: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: UUID('d') }),
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    visibility = { isBlockedBetween: jest.fn().mockResolvedValue(false) };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SyncService,
        { provide: PrismaService, useValue: prisma },
        { provide: MeshRelayService, useValue: { fetchInbox: jest.fn().mockResolvedValue([]) } },
        { provide: FirebaseSyncService, useValue: { mirrorPending: jest.fn() } },
        { provide: WebhooksService, useValue: { onSyncCompleted: jest.fn() } },
        { provide: ContentVisibilityService, useValue: visibility },
      ],
    }).compile();

    service = module.get<SyncService>(SyncService);
  });

  it('ingests a queued message when there is no block', async () => {
    const result = await service.sync(ME, { pendingMessages: [pending] } as any);

    expect(prisma.message.create).toHaveBeenCalled();
    expect(result.acknowledgedMessageIds).toEqual(['cm_1']);
  });

  it('drops a queued message for a blocked recipient without acknowledging it',
    async () => {
      visibility.isBlockedBetween.mockResolvedValue(true);

      const result = await service.sync(ME, {
        pendingMessages: [pending],
      } as any);

      expect(prisma.message.create).not.toHaveBeenCalled();
      expect(result.acknowledgedMessageIds).toEqual([]);
    });

  it('still drops a queued message for a conversation it is not a member of',
    async () => {
      prisma.conversationMember.findUnique.mockResolvedValue(null);

      const result = await service.sync(ME, {
        pendingMessages: [pending],
      } as any);

      expect(prisma.message.create).not.toHaveBeenCalled();
      expect(visibility.isBlockedBetween).not.toHaveBeenCalled();
      expect(result.acknowledgedMessageIds).toEqual([]);
    });
});
