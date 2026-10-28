"""Encaminhamento TCP de desenvolvimento para um único backend fixo.

Não interpreta HTTP, não reescreve Host/Origin e não acessa SQLite/controller.
O bind no host é limitado a loopback pelo Compose. O backend conserva as guardas.
"""

import asyncio
import os
import signal

UPSTREAM = "totem-edge-simulation"
PORT = 8000


async def pipe(reader, writer):
    while data := await reader.read(65536):
        writer.write(data)
        await writer.drain()
    if writer.can_write_eof():
        writer.write_eof()


async def forward(reader, writer):
    upstream = None
    tasks = []
    try:
        remote, upstream = await asyncio.wait_for(
            asyncio.open_connection(UPSTREAM, PORT), timeout=3
        )
        tasks = [
            asyncio.create_task(pipe(reader, upstream)),
            asyncio.create_task(pipe(remote, writer)),
        ]
        await asyncio.gather(*tasks)
    except (OSError, TimeoutError, ConnectionError):
        pass
    finally:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        for connection in (upstream, writer):
            if connection is not None:
                connection.close()
                try:
                    await connection.wait_closed()
                except OSError:
                    pass


async def serve():
    if os.getenv("BINGO_SIMULATION_CONTEXT") not in {"development", "test"}:
        raise RuntimeError("SIMULATION_PROXY_CONTEXT_REQUIRED")
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)
    connections = set()

    def connected(reader, writer):
        task = asyncio.create_task(forward(reader, writer))
        connections.add(task)
        task.add_done_callback(connections.discard)

    async with await asyncio.start_server(connected, "0.0.0.0", PORT):
        await stop.wait()
    tasks = tuple(connections)
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)


if __name__ == "__main__":
    asyncio.run(serve())
