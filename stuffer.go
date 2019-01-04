package main

import (
	"math/rand"
	"net/http"
	"strconv"
)

const chunkSize = 1024 * 1024

func ServeRandomBlob(w http.ResponseWriter, r *http.Request) {
	bytesParam := r.URL.Query().Get("bytes")
	bytesToSend, err := strconv.Atoi(bytesParam)
	if err != nil {
		http.Error(w, "?bytes= parameter is required", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Connection", "close")
	w.Header().Set("Content-Length", bytesParam)

	wholeChunks := bytesToSend / chunkSize
	remainingChunk := bytesToSend % chunkSize
	buf := make([]byte, chunkSize)
	rand.Read(buf)

	for i := 0; i < wholeChunks; i++ {
		w.Write(buf)
	}
	if remainingChunk > 0 {
		smallerBuf := make([]byte, remainingChunk)
		copy(buf, smallerBuf)
		w.Write(smallerBuf)
	}
}

func main() {
	http.Handle("/", http.HandlerFunc(ServeRandomBlob))
	http.ListenAndServe(":9395", nil)
}
