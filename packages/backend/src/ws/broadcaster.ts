import { ZukoWSMessage } from "./messages";

export class Broadcaster {
  private clients = new Set<(msg: string) => void>();

  subscribe(clientSender: (msg: string) => void): () => void {
    this.clients.add(clientSender);
    return () => this.clients.delete(clientSender);
  }

  broadcast(message: ZukoWSMessage): void {
    const payload = JSON.stringify(message);
    for (const send of this.clients) {
      try {
        send(payload);
      } catch {
        this.clients.delete(send);
      }
    }
  }

  getClientCount(): number {
    return this.clients.size;
  }
}
