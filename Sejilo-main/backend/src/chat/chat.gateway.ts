import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Server, WebSocket } from 'ws';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { PushService } from './push.service';

interface AuthenticatedSocket extends WebSocket {
  userId?: string;
  isAlive?: boolean;
}

@WebSocketGateway({ path: '/v1/chat/ws' })
export class ChatGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(ChatGateway.name);
  private readonly userSockets = new Map<string, Set<AuthenticatedSocket>>();

  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly push: PushService,
  ) {}

  afterInit(server: Server) {
    this.logger.log('WebSocket Gateway initialized on /v1/chat/ws');

    // Setup heartbeat interval (30s)
    setInterval(() => {
      for (const [userId, sockets] of this.userSockets.entries()) {
        for (const ws of sockets) {
          if (ws.readyState === WebSocket.OPEN) {
            ws.ping();
            void this.redis.setUserOnline(userId, 60);
          }
        }
      }
    }, 30000);
  }

  async handleConnection(client: AuthenticatedSocket, request: any) {
    try {
      const url = new URL(request.url ?? '', 'http://localhost');
      const token =
        url.searchParams.get('token') ||
        request.headers['authorization']?.replace(/^Bearer /i, '');

      if (!token) {
        client.close(1008, 'Authentication required');
        return;
      }

      const payload = this.jwtService.verify(token);
      const userId = payload.sub || payload.userId;
      const sessionId = payload.sessionId;

      // Reject revoked, expired, or missing sessions (parity with REST guard)
      if (sessionId) {
        const session = await this.prisma.session.findUnique({
          where: { id: sessionId },
        });
        if (
          !session ||
          session.userId !== userId ||
          session.revokedAt ||
          session.expiresAt < new Date()
        ) {
          client.close(1008, 'Session revoked or expired');
          return;
        }
      }

      client.userId = userId;
      client.isAlive = true;

      // Track socket
      if (!this.userSockets.has(userId)) {
        this.userSockets.set(userId, new Set());
        // Subscribe to user Redis channel
        this.redis.subscribe(`user:${userId}:events`, (msgStr) => {
          const userSet = this.userSockets.get(userId);
          if (userSet) {
            for (const ws of userSet) {
              if (ws.readyState === WebSocket.OPEN) {
                ws.send(msgStr);
              }
            }
          }
        });
      }

      this.userSockets.get(userId)!.add(client);
      await this.redis.setUserOnline(userId, 60);

      client.send(JSON.stringify({ type: 'ready', userId }));
      this.logger.log(`User ${userId} connected via WebSocket`);

      client.on('message', async (data: any) => {
        try {
          const parsed = JSON.parse(data.toString());
          if (parsed.type === 'ping') {
            client.send(JSON.stringify({ type: 'pong' }));
            await this.redis.setUserOnline(userId, 60);
          } else if (parsed.type === 'typing') {
            const convId = parsed.conversationId;
            const isTyping = Boolean(parsed.isTyping);
            await this.redis.setTyping(convId, userId, 5);

            const sender = await this.prisma.user.findUnique({
              where: { id: userId },
              include: { profile: true },
            });

            // Broadcast typing to conversation members
            const members = await this.prisma.conversationMember.findMany({
              where: { conversationId: convId, leftAt: null },
              select: { userId: true },
            });

            for (const m of members) {
              if (m.userId !== userId) {
                await this.redis.publish(`user:${m.userId}:events`, JSON.stringify({
                  type: 'typing',
                  conversationId: convId,
                  userId,
                  username: sender?.profile?.username ?? '',
                  isTyping,
                }));
              }
            }
          }
        } catch (_) {}
      });
    } catch (err) {
      client.close(1008, 'Invalid authentication token');
    }
  }

  async handleDisconnect(client: AuthenticatedSocket) {
    if (client.userId && this.userSockets.has(client.userId)) {
      const set = this.userSockets.get(client.userId)!;
      set.delete(client);
      if (set.size === 0) {
        this.userSockets.delete(client.userId);
        await this.redis.setUserOffline(client.userId);
      }
      this.logger.log(`User ${client.userId} disconnected from WebSocket`);
    }
  }
}
