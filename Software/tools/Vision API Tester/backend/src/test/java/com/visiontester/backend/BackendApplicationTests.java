package com.visiontester.backend;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

import org.junit.jupiter.api.Test;

class BackendApplicationTests {

	@Test
	void applicationCanBeInstantiated() {
		assertDoesNotThrow(BackendApplication::new);
	}

}
