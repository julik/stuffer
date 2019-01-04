package main

import (
	"math/rand"
	"net/http"
	"strconv"
)

const chunkSize = 8 * 1024 // Same as Async::IO::Stream::BLOCK_SIZE

func ServeRandomBlob(w http.ResponseWriter, r *http.Request) {
	bytesParam := r.URL.Query().Get("bytes")
	bytesToSend, err := strconv.Atoi(bytesParam)
	if err != nil {
		http.Error(w, "?bytes= parameter is required", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Connection", "close")
	w.Header().Set("Content-Length", bytesParam)

	buf := make([]byte, chunkSize)
	rand.Read(buf)

	wholeChunks := bytesToSend / chunkSize
	for i := 0; i < wholeChunks; i++ {
		w.Write(buf)
	}

	remainingChunk := bytesToSend % chunkSize
	if remainingChunk > 0 {
		w.Write(buf[0:remainingChunk])
	}
}

func main() {
	http.Handle("/", http.HandlerFunc(ServeRandomBlob))
	http.ListenAndServe(":9395", nil)
}
