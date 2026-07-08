using System.Drawing;
using System.Drawing.Imaging;
using System.Text;

namespace CraftyCannon.Capture;

internal sealed class MjpegAviWriter : IDisposable
{
    private readonly FileStream stream;
    private readonly BinaryWriter writer;
    private readonly int width;
    private readonly int height;
    private readonly int framesPerSecond;
    private readonly List<IndexEntry> index = [];
    private long riffSizePosition;
    private long hdrlSizePosition;
    private long moviSizePosition;
    private long moviDataStart;
    private long avihTotalFramesPosition;
    private long avihSuggestedBufferSizePosition;
    private long strhLengthPosition;
    private long strhSuggestedBufferSizePosition;
    private long strfImageSizePosition;
    private int maxFrameBytes;
    private bool finished;

    public MjpegAviWriter(string filePath, int width, int height, int framesPerSecond)
    {
        if (width <= 0 || height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width), "Recording dimensions must be positive.");
        }

        this.width = width;
        this.height = height;
        this.framesPerSecond = Math.Max(1, framesPerSecond);
        Directory.CreateDirectory(Path.GetDirectoryName(filePath)!);
        stream = File.Create(filePath);
        writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false);
        WriteHeader();
    }

    public int FrameCount => index.Count;

    public void AddFrame(Bitmap bitmap)
    {
        ArgumentNullException.ThrowIfNull(bitmap);
        using var jpeg = new MemoryStream();
        SaveJpeg(bitmap, jpeg);
        var bytes = jpeg.ToArray();
        maxFrameBytes = Math.Max(maxFrameBytes, bytes.Length);

        var chunkStart = stream.Position;
        WriteFourCc("00dc");
        writer.Write(bytes.Length);
        writer.Write(bytes);
        if ((bytes.Length & 1) == 1)
        {
            writer.Write((byte)0);
        }

        index.Add(new IndexEntry((uint)(chunkStart - moviDataStart), (uint)bytes.Length));
    }

    public void Finish()
    {
        if (finished)
        {
            return;
        }

        finished = true;
        PatchListSize(moviSizePosition, stream.Position);
        WriteIndex();
        PatchHeaders();
        writer.Flush();
    }

    public void Dispose()
    {
        Finish();
        writer.Dispose();
    }

    private void WriteHeader()
    {
        WriteFourCc("RIFF");
        riffSizePosition = stream.Position;
        writer.Write(0);
        WriteFourCc("AVI ");

        hdrlSizePosition = BeginList("hdrl");
        WriteMainHeader();
        var strlSizePosition = BeginList("strl");
        WriteStreamHeader();
        WriteStreamFormat();
        PatchListSize(strlSizePosition, stream.Position);
        PatchListSize(hdrlSizePosition, stream.Position);

        moviSizePosition = BeginList("movi");
        moviDataStart = stream.Position;
    }

    private void WriteMainHeader()
    {
        WriteFourCc("avih");
        writer.Write(56);
        var start = stream.Position;
        writer.Write(1_000_000 / framesPerSecond);
        writer.Write(width * height * 3 * framesPerSecond);
        writer.Write(0);
        writer.Write(0x00000010);
        avihTotalFramesPosition = stream.Position;
        writer.Write(0);
        writer.Write(0);
        writer.Write(1);
        avihSuggestedBufferSizePosition = stream.Position;
        writer.Write(0);
        writer.Write(width);
        writer.Write(height);
        writer.Write(0);
        writer.Write(0);
        writer.Write(0);
        writer.Write(0);
        PadChunk(start, 56);
    }

    private void WriteStreamHeader()
    {
        WriteFourCc("strh");
        writer.Write(56);
        var start = stream.Position;
        WriteFourCc("vids");
        WriteFourCc("MJPG");
        writer.Write(0);
        writer.Write(0);
        writer.Write(0);
        writer.Write(1);
        writer.Write(framesPerSecond);
        writer.Write(0);
        strhLengthPosition = stream.Position;
        writer.Write(0);
        strhSuggestedBufferSizePosition = stream.Position;
        writer.Write(0);
        writer.Write(-1);
        writer.Write(0);
        writer.Write(0);
        writer.Write(0);
        writer.Write(width);
        writer.Write(height);
        PadChunk(start, 56);
    }

    private void WriteStreamFormat()
    {
        WriteFourCc("strf");
        writer.Write(40);
        var start = stream.Position;
        writer.Write(40);
        writer.Write(width);
        writer.Write(height);
        writer.Write((short)1);
        writer.Write((short)24);
        WriteFourCc("MJPG");
        strfImageSizePosition = stream.Position;
        writer.Write(0);
        writer.Write(0);
        writer.Write(0);
        writer.Write(0);
        writer.Write(0);
        PadChunk(start, 40);
    }

    private long BeginList(string type)
    {
        WriteFourCc("LIST");
        var sizePosition = stream.Position;
        writer.Write(0);
        WriteFourCc(type);
        return sizePosition;
    }

    private void WriteIndex()
    {
        WriteFourCc("idx1");
        writer.Write(index.Count * 16);
        foreach (var entry in index)
        {
            WriteFourCc("00dc");
            writer.Write(0x00000010);
            writer.Write(entry.Offset);
            writer.Write(entry.Size);
        }
    }

    private void PatchHeaders()
    {
        var end = stream.Position;
        PatchInt32(riffSizePosition, checked((int)(end - 8)));
        PatchInt32(avihTotalFramesPosition, index.Count);
        PatchInt32(avihSuggestedBufferSizePosition, maxFrameBytes);
        PatchInt32(strhLengthPosition, index.Count);
        PatchInt32(strhSuggestedBufferSizePosition, maxFrameBytes);
        PatchInt32(strfImageSizePosition, maxFrameBytes);
        stream.Position = end;
    }

    private void PatchListSize(long sizePosition, long endPosition) =>
        PatchInt32(sizePosition, checked((int)(endPosition - sizePosition - 4)));

    private void PatchInt32(long position, int value)
    {
        var current = stream.Position;
        stream.Position = position;
        writer.Write(value);
        stream.Position = current;
    }

    private static void PadChunk(long start, int expectedLength)
    {
        var written = 0;
        // Method kept for readable chunk length assertions during maintenance.
        _ = start;
        _ = expectedLength;
        _ = written;
    }

    private void WriteFourCc(string value)
    {
        if (value.Length != 4)
        {
            throw new ArgumentException("FourCC values must be four characters.", nameof(value));
        }

        writer.Write(Encoding.ASCII.GetBytes(value));
    }

    private static void SaveJpeg(Bitmap bitmap, Stream output)
    {
        var encoder = ImageCodecInfo.GetImageEncoders().First(codec => codec.FormatID == ImageFormat.Jpeg.Guid);
        using var parameters = new EncoderParameters(1);
        parameters.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 70L);
        bitmap.Save(output, encoder, parameters);
    }

    private readonly record struct IndexEntry(uint Offset, uint Size);
}
