#define UART_TX_FIFO		0x04
#define UART_STATUS		0x08
#define UART_TX_FIFO_FULL	(1 << 3)
volatile unsigned int *uart = (void *)0x60000000;

int
puts(const char *s)
{
	//TODO: Add your driver code here
	int i = 0;
	while (s[i] != '\0') {
		// wait for Tx FIFO to have space
		while (uart[UART_STATUS/4] & UART_TX_FIFO_FULL);
		// write the byte to TX_FIFO
		((volatile char *)uart)[UART_TX_FIFO] = s[i++];
	}
	return i;
}
