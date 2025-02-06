/*--------------------------------------------------------------------
	Amiga-Atari Bitmap Converter
	Supports bitmap, HAM, RGB, sprite sheets, Color reduction etc...
	GPU speed enhanced
	Written by Arnaud Carré aka Leonard/Oxygene (@leonard_coder)
--------------------------------------------------------------------*/

#define	MY_THREAD_GROUP_SIZE		64


RWByteAddressBuffer inOutErrors : register(u0);
ByteAddressBuffer inImage : register(t0);

cbuffer processInfo : register(b0)		// read only!
{
	uint	m_w;
	uint	m_h;
	uint	m_palEntry;
	uint	m_pad;
	uint4	inPalette[16];		// These will be correct 9-bits set from brute color.
};

int	GetR(uint c)
{
	return (c >> 8) & 15;
}
int	GetG(uint c)
{
	return (c >> 4) & 15;
}
int	GetB(uint c)
{
	return (c >> 0) & 15;
}

uint	DistanceR(int r0, int r1)
{
	int dr = (r0 - r1) * 3;
	return dr * dr;
}
uint	DistanceG(int g0, int g1)
{
	int dg = (g0 - g1) * 4;
	return dg * dg;
}
uint	DistanceB(int b0, int b1)
{
	int db = (b0 - b1) * 2;
	return db * db;
}

uint	Distance(uint c0, uint c1)
{
	return DistanceR(GetR(c0), GetR(c1)) +
	DistanceG(GetG(c0), GetG(c1)) +
	DistanceB(GetB(c0), GetB(c1));
}

uint GetArchiePal(in uint i, in uint bruteRGB)
{
    uint colPal = ((i & 15) == m_palEntry) ? bruteRGB : inPalette[i & 15].x;
		
    int R = ((i & 0x10) >> 1) | (GetR(colPal) & 0x7);
    int G = ((i & 0x60) >> 3) | (GetG(colPal) & 0x3);
    int B = ((i & 0x80) >> 4) | (GetB(colPal) & 0x7);
		
    return (R << 8) | (G << 4) | B;
}

uint getBestColor(in uint original, in int scanline, in uint bruteRGB)
{
	uint err = 0xffffffff;

	// try to find a better solution in the palette
	uint d;

	[loop]
	for (uint p = 0; p < 256; p++)
	{
        uint colPal = GetArchiePal(p, bruteRGB);
		d = Distance(original,colPal);
		err = (d < err) ? d : err;
	}

    return err;
}

uint	LineErrorCompute(in int scanline, in uint bruteForceColor)
{
    uint bruteRGB = ((bruteForceColor & 0x7) << 8) | (((bruteForceColor >> 3) & 0x7) << 4) | ((bruteForceColor >> 6) & 0x7);
	
    uint err = 0;
	uint readImgAd = scanline * m_w * 4;
	[loop]
	for (uint x = 0; x < m_w; x++)
	{
		// search best fit in palette
		err += getBestColor(inImage.Load(readImgAd), scanline, bruteRGB);
		readImgAd += 4;
	}
    return err;
}

[numthreads(MY_THREAD_GROUP_SIZE, 1, 1)]
void ArchiePalKernel( uint3 DTid : SV_GroupID, uint3 TGid : SV_GroupThreadID)
{
	uint bruteColor = DTid.y*MY_THREAD_GROUP_SIZE+TGid.x;
	uint scanline = DTid.x;

	uint err = LineErrorCompute(scanline, bruteColor);

	inOutErrors.InterlockedAdd(bruteColor * 4, err);	// this sums the error over all scanlines for each bruteColor...
}
