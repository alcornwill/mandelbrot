// this program creates a .bmp file in the working directory

#include <math.h>
#include <fstream>
#include <windows.h> // contains windef.h which has all the bitmap stuff
#include <stdio.h> // defines FILENAME_MAX
#include <direct.h>

using namespace std;

// dimensions are hard coded
#define WIDTH 4096
#define HEIGHT 4096

// this kernel calculates the pixel value for one pixel
__global__ void mandelbrot(BYTE* imageData, float unitX, float unitY, int max, int pixelWidth)
{
	// get the unique thread index
	// only using 1, 1 grid
    int row = blockIdx.y * blockDim.y + threadIdx.y;
	int col = blockIdx.x * blockDim.x + threadIdx.x;

	// offset values so center is 0, 0
	float offsetWidth = col - (WIDTH / 2);
	float offsetHeight = row - (HEIGHT / 2);

	// multiply by our units (applies the zoom)
	float translatedWidth = offsetWidth * unitX;
	float translatedHeight = offsetHeight * unitY;

	float x = 0, y = 0;
	int iter = 0;

	int pos = (WIDTH * row) + col; // the position in the pixel data byte array

	// keep iterating until point escapes mandlebrot set
	while (1)
	{
		if (sqrt((x*x) + (y*y)) > 2) // if magnitude is greater than 2
		{
			// point has escaped mandlebrot set - paint white
			imageData[pos * pixelWidth] = (BYTE)255;
			break;
		}
		if (iter == max)
		{
			// point is in the mandlebrot set - paint black
			imageData[pos * pixelWidth] = (BYTE)0;
			break;
		}

		// this applies the mandelbrot equation
		// Zn+1 = Zn^2 + C
		float x_new = ((x*x) - (y*y)) + translatedWidth;
		y = (2 * x*y) + translatedHeight;
		x = x_new;
		iter++;
	}
}

int main(int argc, char* argv[])
{
	printf("Building image data...\n");

    // this is hard coded sadly
	dim3 grid(256, 256);
	dim3 block(16, 16);

	int pixelWidth = 1; // in bytes. bmp doesn't really do binary images so 1 byte is minimum
	int imageSize = WIDTH * HEIGHT * pixelWidth; // in bytes

	// allocate device memory
	BYTE * imageData_d = NULL;
	cudaMalloc((void **)&imageData_d, imageSize);

	// the interesting stuff in the mandlebrot set occurs between -2,-2 and 2,2
	float zoomX = 2, zoomY = 2;

	// max iterations
	// increasing iterations improves image quality but hits performance
	int max = 100;

	float unitX = zoomX / (WIDTH / 2);
	float unitY = zoomY / (HEIGHT / 2);

	// launch kernel on each pixel
	mandelbrot<<<grid, block>>>(imageData_d, unitX, unitY, max, pixelWidth);

	// copy data back to host
	BYTE * imageData_h = (BYTE*)malloc(imageSize);
	cudaMemcpy(imageData_h, imageData_d, imageSize, cudaMemcpyDeviceToHost);

    // construct the bitmap info header (DIB header)
	BITMAPINFOHEADER bmpInfoHeader = { 0 };
	bmpInfoHeader.biSize = sizeof(BITMAPINFOHEADER); // should be 40 bytes
	bmpInfoHeader.biHeight = HEIGHT;
	bmpInfoHeader.biWidth = WIDTH;
	bmpInfoHeader.biPlanes = 1; // number of color planes (always 1)
	bmpInfoHeader.biBitCount = pixelWidth * 8;
	bmpInfoHeader.biCompression = BI_RGB; // do not compress
	bmpInfoHeader.biSizeImage = imageSize; // image size in bytes
	bmpInfoHeader.biClrUsed = 0; // no colors
	bmpInfoHeader.biClrImportant = 0; // all colors important

	// construct bitmap file header
	BITMAPFILEHEADER bfh;
	bfh.bfType = 0x4D42; // the first two bytes of the file are 'BM' in ASCII, in little endian
	bfh.bfOffBits = sizeof(BITMAPINFOHEADER) + sizeof(BITMAPFILEHEADER) + (sizeof(RGBQUAD) * 256); // the offset (starting address of pixel data). size of headers + color table
	bfh.bfSize = bfh.bfOffBits + bmpInfoHeader.biSizeImage; // total size of image including size of headers

	// create the color table
	RGBQUAD colorTable[256];
	for (int i = 0; i < 256; i++)
	{
		colorTable[i].rgbBlue = (BYTE)i;
		colorTable[i].rgbGreen = (BYTE)i;
		colorTable[i].rgbRed = (BYTE)i;
		colorTable[i].rgbReserved = (BYTE)i;
	}

	// write everything to file
	ofstream imageFile;

	char filePath[FILENAME_MAX];
	// get the current working directory
	if (!_getcwd(filePath, FILENAME_MAX))
	{
		printf("error accessing current working directory\n");
		return 0;
	}

	printf("The current working directory is %s\n", filePath);
	strcat_s(filePath, "\\mandelbrot.bmp"); // append the image file name

	imageFile.open(filePath);
	imageFile.write((char *)&bfh, sizeof(bfh)); // Write the File header
	imageFile.write((char *)&bmpInfoHeader, sizeof(bmpInfoHeader)); // Write the bitmap info header
	imageFile.write((char *)&colorTable, sizeof(RGBQUAD) * 256); // Write the color table

	// if number of rows is a multiple of 4 bytes
	if (WIDTH % 4 == 0)
	{
		// write the image judata
		imageFile.write((char*)imageData_h, bmpInfoHeader.biSizeImage);
	}
	else
	{
		// else write and pad each row out with empty bytes
		char* padding = new char[4 - WIDTH % 4];
		for (int i = 0; i < HEIGHT; ++i)
		{
			imageFile.write((char *)&imageData_h[i * WIDTH], WIDTH);
			imageFile.write((char *)padding, 4 - WIDTH % 4);
		}
	}

	imageFile.close();
	printf("image file saved to %s\n", filePath);

	// clean up
	cudaDeviceReset();
	cudaFree(imageData_d);
	free(imageData_h);

	return 0;
}
