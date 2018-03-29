﻿using System;
using System.IO;
using System.IO.Pipes;
using System.Runtime.Serialization.Formatters.Binary;
using System.Threading;
using System.Threading.Tasks;

namespace AsyncAsDesigned.PerfLib
{
    public class NamedPipeServerAsync : IDisposable
    {

        string pipeName;
        static BinaryFormatter formatter = new BinaryFormatter();

        object lockCancel = new object();
        private CancellationTokenSource cancelWaitForConnection;
        bool closed = false;

        public delegate Task TokenReceivedAsync(Token token);
        public event TokenReceivedAsync TokenReceivedEventAsync;

        public NamedPipeServerAsync(string pipeName)
        {
            this.pipeName = pipeName;
        }

        public Task StartAsync(bool oneMessage = false)
        {
            return Listen(oneMessage);
        }

        private async Task Listen(bool oneMessage = false)
        {
            using (var pipeServer = new NamedPipeServerStream(pipeName, PipeDirection.In, NamedPipeServerStream.MaxAllowedServerInstances, PipeTransmissionMode.Byte, PipeOptions.Asynchronous))
            {
                lock (lockCancel)
                {
                    if(closed) { return; } // Comment this out, run all tests, SendReceiveMultiple blocks. 
                    cancelWaitForConnection = new CancellationTokenSource();
                }

                try
                {
                    await pipeServer.WaitForConnectionAsync(cancelWaitForConnection.Token).ConfigureAwait(false);
                }
                catch (System.OperationCanceledException) { closed = true; } // Thrown when CancallationTokenSource.Cancel() is called

                lock (lockCancel)
                {
                    cancelWaitForConnection = null;
                }

                if (!closed)
                {
                    var token = Received(pipeServer);

                    await (TokenReceivedEventAsync?.Invoke(token) ?? Task.CompletedTask).ConfigureAwait(false);

                    pipeServer.Close();
                }

            }

            if (!oneMessage && !closed) { await Listen().ConfigureAwait(false); } // Recursive loop unless we only want to receive one message

        }

        private static Token Received(NamedPipeServerStream namedPipeServerStream)
        {
            int len = 0;

            len = namedPipeServerStream.ReadByte() * 256;
            len += namedPipeServerStream.ReadByte();
            byte[] inBuffer = new byte[len];
            namedPipeServerStream.Read(inBuffer, 0, len);

            Token token;

            using (var mem = new MemoryStream(inBuffer))
            {
                token = (Token)formatter.Deserialize(mem);
            }

            namedPipeServerStream.Disconnect();
            namedPipeServerStream.Dispose();

            return token;


        }

        public void Dispose()
        {
            lock (lockCancel)
            {
                closed = true;
                if (cancelWaitForConnection != null)
                {
                    cancelWaitForConnection.Cancel();
                }
            }
        }
    }
}
